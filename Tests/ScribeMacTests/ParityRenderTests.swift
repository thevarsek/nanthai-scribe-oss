import AppKit
import ScribeCore
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PAR1_RENDER_DIR"] != nil))
struct ParityRenderTests {
    @Test func renderRecoveryStates() async throws {
        _ = NSApplication.shared
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["PAR1_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = destination.appending(path: "fixtures-mac")
        let name = "PAR1-Renders-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let damagedNotes = NoteStore(root: root.appending(path: "history.notes"))
        try damagedNotes.save([])
        try Data("corrupt".utf8).write(to: damagedNotes.file(UUID()))
        try JSONEncoder().encode(LastDictationRecovery(text: "Synthetic recovered dictation"))
            .write(to: root.appending(path: "history.last.json"), options: .atomic)
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        let recorder = MeetingRecorder(root: root.appending(path: "Meetings"), defaults: defaults)
        let bad = root.appending(path: "Meetings/\(UUID())")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: bad.appending(path: "meeting.json"))
        await recorder.load()
        for scheme in [ColorScheme.light, .dark] {
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let suffix = scheme == .light ? "light" : "dark"
            func shot(_ name: String, _ view: some View) async throws {
                try await render(view, scheme: scheme, to: destination.appending(path: "mac-\(name)-\(suffix).png"))
            }
            let take = try RetainedDictation(root: root.appending(path: "Retry"), languages: ["en-GB"])
            dictation.previewReliability(takes: [take])
            try await shot("dictation-recovery", VStack(alignment: .leading) { MenuContent(dictation: dictation, recorder: recorder, navigation: LibraryNavigation()) }.padding().frame(width: 420))
            var meeting = Meeting(title: "Project review", duration: 71,
                speakers: [.init(id: "you", name: "You")], turns: [.init(speakerID: "you", start: 0, end: 8, text: "The review is on Thursday.")],
                summary: .init(bullets: ["Review scheduled."]), audio: [.init(stream: "you", file: "microphone.caf", offset: 0)])
            meeting.processingError = "Couldn't transcribe. Your recording is kept for Retry."
            try await shot("retry-transcription", detail(meeting).frame(width: 660, height: 620))
            meeting.editTurn(meeting.turns[0].id, text: "The review is on Friday.")
            meeting.processingError = nil
            try await shot("update-summary", detail(meeting).frame(width: 660, height: 620))
            try await shot("unreadable-note", LibraryView(dictation: dictation, recorder: recorder, navigation: LibraryNavigation()).frame(width: 900, height: 600))
            try await nativeAlert("Couldn't save", message: "Couldn't save notes. Your changes are still here.", scheme: scheme,
                to: destination.appending(path: "mac-save-failed-\(suffix).png"))
            try await shot("unreadable-meeting", List { MeetingRows(recorder: recorder) { $0 } }.frame(width: 420, height: 180))
            recorder.previewPreparation(0.43)
            try await shot("meeting-preparing", MeetingsDetail(recorder: recorder, dictation: dictation, selection: nil).frame(width: 660, height: 560))
            recorder.previewPreparation(nil)
            dictation.previewReliability(progress: 0.43)
            try await shot("dictation-preparing", HUDView(dictation: dictation).frame(width: 580, height: 180))
            try await shot("speech-download", SettingsPane(tab: .languages, dictation: dictation, loginItem: LoginItem()).frame(width: 600, height: 500))
            dictation.previewReliability(languageError: "Couldn't prepare this language. Try again.")
            try await shot("language-error", SettingsPane(tab: .languages, dictation: dictation, loginItem: LoginItem()).frame(width: 600, height: 500))
            for (name, error) in [("edit-failed", DictationFailure.edit), ("refine-failed", DictationFailure.refine)] {
                dictation.previewReliability(error: error)
                try await shot(name, HUDView(dictation: dictation).frame(width: 580, height: 180))
            }
        }
    }
    private func nativeAlert(_ title: String, message: String, scheme: ColorScheme, to url: URL) async throws {
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "Retry"); alert.addButton(withTitle: "OK")
        let source = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        alert.icon = NSImage(contentsOf: source.appending(path: "Resources/AppIcon.icns"))
        alert.layout()
        alert.window.isReleasedWhenClosed = false
        alert.window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        alert.window.orderFrontRegardless()
        defer { alert.window.close() }
        let view = try #require(alert.window.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let snapshot = NSImage(size: view.bounds.size); snapshot.addRepresentation(bitmap)
        let renderer = ImageRenderer(content: ZStack {
            Color(nsColor: .windowBackgroundColor)
            Image(nsImage: snapshot)
        }.frame(width: view.bounds.width, height: view.bounds.height).environment(\.colorScheme, scheme))
        renderer.scale = 2
        let png = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        try #require(png.representation(using: .png, properties: [:])).write(to: url)
    }
    private func detail(_ meeting: Meeting) -> some View {
        MeetingDetailView(meeting: meeting, update: { _ in }, updateTitle: { _ in }, regenerate: {}, retry: {})
    }
    private func render(_ view: some View, scheme: ColorScheme, to url: URL) async throws {
        let controller = NSHostingController(rootView: view.environment(\.colorScheme, scheme).environment(\.appearsActive, true))
        let host = controller.view
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: host.frame.size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        window.makeFirstResponder(nil)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let snapshot = NSImage(size: host.bounds.size); snapshot.addRepresentation(bitmap)
        let renderer = ImageRenderer(content: ZStack {
            Color(nsColor: .windowBackgroundColor)
            Image(nsImage: snapshot)
        }.frame(width: host.bounds.width, height: host.bounds.height).environment(\.colorScheme, scheme))
        renderer.scale = 2
        let png = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        try #require(png.representation(using: .png, properties: [:])).write(to: url)
    }
}
