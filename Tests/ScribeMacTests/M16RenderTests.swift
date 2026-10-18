import AppKit
import ScribeCore
import ScreenCaptureKit
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M16_RENDER_DIR"] != nil))
struct M16RenderTests {
    @Test func renderLibraryAndMeetings() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M16_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let domain = "M16Renders-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let root = destination.appending(path: "mac-fixtures")
        try? FileManager.default.removeItem(at: root)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        let recorder = MeetingRecorder(root: root.appending(path: "meetings"), defaults: defaults)
        var note = dictation.createNote(text: "Project review\n\nLet's meet tomorrow at ten. Please bring the project notes and the revised schedule.\n\nWe'll confirm the milestones and send the final invitation after the review.")
        note.pinned = true
        dictation.saveNote(note)
        dictation.createNote(text: "Confirm the review time before sending invitations.")
        let older = Note(createdAt: .now.addingTimeInterval(-86_400), text: "The studio entrance is on the left. Ring the bell and I'll come down to meet you.", origin: .pasted)
        dictation.saveNote(older)
        let meeting = Meeting(title: "Product review", duration: 1284,
            speakers: [.init(id: "you", name: "You"), .init(id: "a", name: "Sam")],
            turns: [.init(speakerID: "a", start: 0, end: 9, text: "The prototype is ready. Let's review accessibility before Friday's launch."),
                    .init(speakerID: "you", start: 10, end: 18, text: "I'll arrange the review for Thursday and invite the support team.")],
            summary: .init(bullets: ["The prototype is ready for review.", "Launch is planned for Friday."],
                           actions: [.init(text: "Arrange Thursday's review", owner: "You")]))
        recorder.meetings = [meeting]
        let navigation = LibraryNavigation()
        navigation.selection = .note(note.id)
        let editor = NoteEditor(note: note)
        for scheme in [ColorScheme.light, .dark] {
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let suffix = scheme == .light ? "light" : "dark"
            try await render(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation, editorOverride: editor)
                .frame(width: 900, height: 600).environment(\.colorScheme, scheme), to: destination.appending(path: "mac-library-\(suffix).png"))
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        await editor.apply(.clearer, rewriter: HighlightRenderRewriter())
        try await render(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation, editorOverride: editor)
            .frame(width: 900, height: 600).environment(\.colorScheme, .light),
            to: destination.appending(path: "mac-library-highlight.png"))
        try await render(SettingsView(dictation: dictation, showOnboarding: {})
            .frame(width: 600, height: 500).environment(\.colorScheme, .light),
            to: destination.appending(path: "mac-settings-tabs.png"))
        var edited = note
        edited.save(editor.text)
        dictation.saveNote(edited)
        editor.showChanges = true
        try await render(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation, editorOverride: editor)
            .frame(width: 900, height: 600).environment(\.colorScheme, .light),
            to: destination.appending(path: "mac-library-changes.png"))
        editor.showChanges = false
        let runningEditor = NoteEditor(note: note)
        runningEditor.selection = NSRange(location: 16, length: 28)
        let task = Task { await runningEditor.apply(.clearer, rewriter: RenderRewriter()) }
        for _ in 0..<100 where !runningEditor.isRunning { await Task.yield() }
        #expect(runningEditor.isRunning)
        NSApp.appearance = NSAppearance(named: .aqua)
        try await render(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation, editorOverride: runningEditor)
            .frame(width: 900, height: 600).environment(\.colorScheme, .light), to: destination.appending(path: "mac-library-running.png"))
        task.cancel()
        await task.value
        navigation.selection = .meeting(meeting.id)
        try await render(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation)
            .frame(width: 900, height: 600), to: destination.appending(path: "mac-library-meetings.png"))
        // This captures the production menu's contents in an offscreen host, without opening the user's menu bar.
        try await render(VStack(alignment: .leading, spacing: 8) {
            MenuContent(dictation: dictation, recorder: recorder, navigation: navigation)
        }.buttonStyle(.plain).padding().frame(width: 420)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light),
            to: destination.appending(path: "mac-menu-open-scribe.png"))

    }

    private func render(_ view: some View, to url: URL, windowServer: Bool = true) async throws {
        let controller = NSHostingController(rootView: view.environment(\.appearsActive, true))
        let host = controller.view
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Scribe"
        window.contentViewController = controller
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        if windowServer {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let target = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * 2)
            configuration.height = Int(window.frame.height * 2)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
        } else {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        }
    }
}

private struct RenderRewriter: TextRewriter {
    let id = "render"
    func isAvailable() async -> Bool { true }
    func rewrite(_ request: RewriteRequest) async throws -> String {
        try await Task.sleep(for: .seconds(15))
        throw CancellationError()
    }
}

private struct HighlightRenderRewriter: TextRewriter {
    let id = "highlight-render"
    func isAvailable() async -> Bool { true }
    func rewrite(_ request: RewriteRequest) async throws -> String {
        "Project review\n\nLet's meet tomorrow at ten to review the revised schedule, confirm milestones, and send the final invitation."
    }
}
