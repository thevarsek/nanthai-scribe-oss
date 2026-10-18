import AppKit
import ScribeMacCore
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M19_RENDER_DIR"] != nil))
struct M19RenderTests {
    @Test func render() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M19_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let domain = "M19-render-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let fixture = destination.appending(path: "fixture")
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: fixture)
        }
        let dictation = Dictation(defaults: defaults, historyURL: fixture.appending(path: "history.json"), vocabularyDirectory: fixture)
        let login = LoginItem()
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            try await save(SettingsPane(tab: .general, dictation: dictation, loginItem: login)
                .frame(width: 600, height: 440).environment(\.colorScheme, scheme),
                to: destination.appending(path: "settings-general-\(appearance).png"))
            for (name, caps, validation): (String, [String], TalkShortcut.Validation) in [
                ("idle", [], .accepted), ("live", ["⌃", "⌥", "Space"], .accepted),
                ("rejected", ["A"], .rejected), ("conflict", ["⌘", "Space"], .conflict)
            ] {
                try await save(TalkShortcutRecorderContent(caps: caps, validation: validation)
                    .background(.background).environment(\.colorScheme, scheme),
                    to: destination.appending(path: "recorder-\(name)-\(appearance).png"))
            }
            try await save(OnboardingPage(step: .tryIt, talkShortcut: .controlOptionSpace)
                .environment(\.colorScheme, scheme),
                to: destination.appending(path: "onboarding-talk-\(appearance).png"))
        }
    }

    private func save(_ view: some View, to url: URL) async throws {
        let controller = NSHostingController(rootView: view.environment(\.appearsActive, true))
        let host = controller.view
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let nativeBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: nativeBitmap)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(nativeBitmap)
        let renderer = ImageRenderer(content: Image(nsImage: image).frame(width: size.width, height: size.height))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }
}
