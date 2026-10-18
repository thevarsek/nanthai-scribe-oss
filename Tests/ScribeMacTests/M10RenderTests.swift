import AppKit
import ScribeCore
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M10_RENDER_DIR"] != nil))
struct M10RenderTests {
    @Test func refineSettings() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M10_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let suite = "M10Render-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = destination.appending(path: "render-fixture")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        let ids = ["com.apple.MobileSMS", "com.apple.Terminal", "com.apple.dt.Xcode", "com.apple.mail"]
        let apps = ids.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).flatMap(AppStyleApplication.init(url:))
        }
        #expect(apps.count == 4)
        dictation.appStyles.set("default", for: "com.apple.mail")
        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }
        for scheme in [ColorScheme.light, .dark] {
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let view = SettingsPane(tab: .polish, dictation: dictation, loginItem: LoginItem(), styleApplications: apps)
                .frame(width: 600, height: 440).environment(\.colorScheme, scheme).environment(\.appearsActive, true)
            // Forms contain AppKit controls; export their offscreen native raster through ImageRenderer.
            let controller = NSHostingController(rootView: view)
            let host = controller.view
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let native = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: native)
            let snapshot = NSImage(size: host.bounds.size)
            snapshot.addRepresentation(native)
            let renderer = ImageRenderer(content: Image(nsImage: snapshot).frame(width: 600, height: 440))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: destination.appending(path: "settings-refine-\(scheme == .light ? "light" : "dark").png"))
            window.close()
        }
    }
}
