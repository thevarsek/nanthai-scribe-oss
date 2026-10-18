import AppKit
import ScribeCore
import ScreenCaptureKit
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M85C_RENDER_DIR"] != nil))
struct M85cRenderTests {
    @Test func settingsWithoutAudioTab() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M85C_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        #expect(CGPreflightScreenCaptureAccess())
        guard CGPreflightScreenCaptureAccess() else { return }
        _ = NSApplication.shared
        let suite = "M85cRender-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = destination.appending(path: "render-fixture")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"),
                                  vocabularyDirectory: root)
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            #expect(!SettingsTab.allCases.map(\.title).contains("Audio"))
            try await render(SettingsView(dictation: dictation, showOnboarding: {})
                .frame(width: 600, height: 500).environment(\.colorScheme, scheme),
                to: destination.appending(path: "mac-settings-\(appearance).png"))
        }
    }

    private func render(_ view: some View, to url: URL) async throws {
        let controller = NSHostingController(rootView: view.environment(\.appearsActive, true))
        let host = controller.view
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Settings"
        window.appearance = NSApp.appearance
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Native glass tab bars cannot be rasterized with cacheDisplay. Capture only
        // this offscreen fixture window, without requesting permission or capturing other windows.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let ownWindow = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int(window.frame.height * 2)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let capture = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: ownWindow), configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: capture)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        window.close()
    }
}
