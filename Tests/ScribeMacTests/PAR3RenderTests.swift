import AppKit
import AVFoundation
import ScribeCore
import ScribeUI
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PAR3_RENDER_DIR"] != nil))
struct PAR3RenderTests {
    @Test func allJourneyStates() async throws {
        _ = NSApplication.shared
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["PAR3_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = destination.appending(path: "mac-fixtures")
        let name = "PAR3-render-\(UUID())", defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        let note = dictation.createNote(text: "Review the launch schedule")
        dictation.deleteNote(note.id)
        let recorder = MeetingRecorder(root: root.appending(path: "Meetings"), defaults: defaults)
        var meeting = Meeting(title: "Friday review", duration: 30,
            speakers: [.init(id: "one", name: "Speaker 1")],
            turns: [.init(speakerID: "one", start: 0, end: 10, text: "We can send the revised schedule on Friday."),
                    .init(speakerID: "one", start: 10, end: 25, text: "The design review is complete. Please share the final notes.")],
            summary: .init(bullets: ["Send the revised schedule on Friday."]),
            audio: [.init(stream: "system", file: "kept.caf", offset: 0)])
        try await recorder.store.save(meeting)
        let folder = recorder.store.directory(meeting.id)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        do {
            let file = try AVAudioFile(forWriting: folder.appending(path: "kept.caf"), settings: format.settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480_000)); buffer.frameLength = 480_000
            try file.write(from: buffer)
        }
        for scheme in [ColorScheme.light, .dark] {
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let suffix = scheme == .light ? "light" : "dark"
            func shot(_ name: String, _ view: some View) async throws {
                try await render(view, scheme: scheme, to: destination.appending(path: "mac-\(name)-\(suffix).png"))
            }
            recorder.meetings = [meeting]
            var deletedMeeting = meeting
            deletedMeeting.id = UUID(); deletedMeeting.deletedAt = .now
            try await shot("recently-deleted", List {
                RecentlyDeletedSection(notes: dictation.deletedNotes, meetings: [deletedMeeting],
                    restoreNote: { _ in }, deleteNote: { _ in }, restoreMeeting: { _ in }, deleteMeeting: { _ in })
            }.frame(width: 440, height: 360))
            try await shot("recently-deleted-empty", List {
                RecentlyDeletedSection(notes: [], meetings: [], restoreNote: { _ in }, deleteNote: { _ in },
                    restoreMeeting: { _ in }, deleteMeeting: { _ in })
            }.frame(width: 440, height: 200))
            try await shot("recently-deleted-menu", VStack(alignment: .leading) {
                Text("Recently Deleted").font(.headline)
                List { Button("Delete All", role: .destructive) {} }
            }.padding().frame(width: 320, height: 160))
            try await shot("record-menu", VStack(alignment: .leading) {
                Text("Record").font(.headline)
                List { Button("Record meeting") {}; Button("Transcribe a Recording…") {} }
            }.padding().frame(width: 340, height: 200))
            try await shot("import-consent", RecordingImportConsent(speakerModelInstalled: false, start: { _ in }, cancel: {}))
            try await shot("import-progress", MeetingDetailView(meeting: meeting, processing: true,
                progress: .init(identifiesSpeakers: true, statuses: [.saving: .done, .transcribing: .active]),
                update: { _ in }, updateTitle: { _ in }, regenerate: {}).frame(width: 640, height: 600))
            try await shot("import-result", MeetingDetailView(meeting: meeting, update: { _ in }, updateTitle: { _ in }, regenerate: {}).frame(width: 640, height: 700))
            try await shot("backup-rows", SettingsPane(tab: .privacy, dictation: dictation, loginItem: LoginItem(), recorder: recorder).frame(width: 600, height: 450))
            try await alert(message: "Library exported.", scheme: scheme, to: destination.appending(path: "mac-backup-export-result-\(suffix).png"))
            try await alert(message: "Backup imported. Your Library has been merged.", scheme: scheme, to: destination.appending(path: "mac-backup-import-result-\(suffix).png"))
            let player = MeetingPlayback(); player.load(meeting, folder: folder)
            for playing in [false, true] {
                player.preview(position: playing ? 4 : 0, playing: playing, duration: 30)
                try await shot(playing ? "player-playing" : "player-idle", MeetingDetailView(meeting: meeting,
                    update: { _ in }, updateTitle: { _ in }, regenerate: {}, audioFolder: folder, playback: player).frame(width: 700, height: 800))
            }
            player.stop()
            meeting.modified = .now
        }
    }
    private func alert(message: String, scheme: ColorScheme, to url: URL) async throws {
        let alert = NSAlert(); alert.messageText = "Library backup"; alert.informativeText = message; alert.addButton(withTitle: "OK"); alert.layout()
        alert.window.isReleasedWhenClosed = false; alert.window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000)); alert.window.orderFrontRegardless()
        defer { alert.window.close() }
        try await bitmap(try #require(alert.window.contentView), scheme: scheme, to: url)
    }
    private func render(_ view: some View, scheme: ColorScheme, to url: URL) async throws {
        let controller = NSHostingController(rootView: view.tint(Brand.coral).environment(\.colorScheme, scheme).environment(\.appearsActive, true))
        let host = controller.view; host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: host.frame.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentViewController = controller
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua); window.orderFrontRegardless()
        defer { window.close() }
        try await bitmap(host, scheme: scheme, to: url)
    }
    private func bitmap(_ view: NSView, scheme: ColorScheme, to url: URL) async throws {
        view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(200))
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: bitmap)
        let snapshot = NSImage(size: view.bounds.size); snapshot.addRepresentation(bitmap)
        let renderer = ImageRenderer(content: ZStack { Color(nsColor: .windowBackgroundColor); Image(nsImage: snapshot) }
            .frame(width: view.bounds.width, height: view.bounds.height).environment(\.colorScheme, scheme))
        renderer.scale = 2
        let png = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        try #require(png.representation(using: .png, properties: [:])).write(to: url)
    }
}
