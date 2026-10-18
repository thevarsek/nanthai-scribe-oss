import AppKit
import ScribeCore
import ScreenCaptureKit
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M7_RENDER_DIR"] != nil))
struct M7RenderTests {
    @Test func renderMeetings() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M7_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let domain = "ScribeM7Renders-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let dictation = Dictation(defaults: defaults, historyURL: destination.appending(path: "history.json"),
                                  vocabularyDirectory: destination.appending(path: "fixture-vocabulary"))
        let recorder = MeetingRecorder(root: destination.appending(path: "meetings"), defaults: defaults)
        let meeting = Meeting(title: "Product review", duration: 1284,
            speakers: [.init(id: "you", name: "You"), .init(id: "a", name: "Sam"), .init(id: "b", name: "Alex")],
            turns: [
                .init(speakerID: "a", start: 0, end: 9, text: "The prototype is ready. Let's review accessibility before Friday's launch."),
                .init(speakerID: "you", start: 10, end: 18, text: "I'll arrange the review for Thursday and invite the support team."),
                .init(speakerID: "b", start: 20, end: 28, text: "I'll send the release notes after the review. The budget stays the same.")],
            summary: .init(bullets: ["The prototype is ready for review.", "The team plans to launch on Friday after the accessibility review.", "The budget remains unchanged."],
                actions: [.init(text: "Arrange Thursday's review", owner: "You"), .init(text: "Share release notes", owner: "Alex", done: true)]))
        recorder.meetings = [meeting]
        recorder.selection = meeting.id
        for scheme in [ColorScheme.light, .dark] {
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let suffix = scheme == .light ? "light" : "dark"
            try await render(MeetingsView(recorder: recorder, dictation: dictation)
                .frame(width: 900, height: 600).environment(\.colorScheme, scheme),
                to: destination.appending(path: "meetings-\(suffix).png"))
            recorder.meetings = []; recorder.selection = nil
            try await render(MeetingsView(recorder: recorder, dictation: dictation)
                .frame(width: 900, height: 600).environment(\.colorScheme, scheme),
                to: destination.appending(path: "empty-\(suffix).png"))
            recorder.meetings = [meeting]; recorder.selection = meeting.id
            try await render(MeetingConsentView(start: { _, _ in }, cancel: {}).environment(\.colorScheme, scheme),
                to: destination.appending(path: "consent-\(suffix).png"))
            try await render(SettingsPane(tab: .meetings, dictation: dictation, loginItem: LoginItem())
                .frame(width: 520, height: 440).environment(\.colorScheme, scheme),
                to: destination.appending(path: "settings-meetings-\(suffix).png"))
            try await render(Image(nsImage: MenuBarIcon.recording).padding().environment(\.colorScheme, scheme),
                to: destination.appending(path: "recording-icon-\(suffix).png"))
        }
    }

    private func render(_ view: some View, to url: URL) async throws {
        // ImageRenderer omits AppKit-backed controls (Form and TextField). Rasterize
        // their real native hosting view first, then export that image with ImageRenderer.
        let controller = NSHostingController(rootView: view.environment(\.appearsActive, true))
        let host = controller.view
        let size = host.fittingSize
        let needsChrome = url.lastPathComponent.hasPrefix("meetings-") || url.lastPathComponent.hasPrefix("empty-")
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: needsChrome ? [.titled, .closable, .resizable] : [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        host.frame = NSRect(origin: .zero, size: size)
        window.title = "Meetings"
        window.alphaValue = needsChrome ? 1 : 0
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        func prepare(_ view: NSView) {
            if let table = view as? NSTableView {
                for row in 0..<table.numberOfRows {
                    table.rowView(atRow: row, makeIfNecessary: true)?.layoutSubtreeIfNeeded()
                    for column in 0..<table.numberOfColumns {
                        table.view(atColumn: column, row: row, makeIfNecessary: true)?.displayIfNeeded()
                    }
                }
            }
            view.subviews.forEach(prepare)
            view.displayIfNeeded()
        }
        prepare(host)
        window.makeFirstResponder(nil)
        if needsChrome {
            // Native source-list cells and toolbar layers are rendered by WindowServer, not cacheDisplay.
            // Capture only this generated offscreen fixture window; never the user's display.
            let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let target = try #require(shareable.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * 2)
            configuration.height = Int(window.frame.height * 2)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
            window.close()
            return
        }
        let capture = host
        let nativeBitmap = try #require(capture.bitmapImageRepForCachingDisplay(in: capture.bounds))
        capture.cacheDisplay(in: capture.bounds, to: nativeBitmap)
        let captureSize = capture.bounds.size
        let snapshot = NSImage(size: captureSize)
        snapshot.addRepresentation(nativeBitmap)
        let renderer = ImageRenderer(content: ZStack { Color(nsColor: .windowBackgroundColor); Image(nsImage: snapshot) }.frame(width: captureSize.width, height: captureSize.height))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        window.close()
    }
}
