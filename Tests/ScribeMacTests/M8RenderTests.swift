import AppKit
import ScribeCore
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M8_RENDER_DIR"] != nil))
struct M8RenderTests {
    @Test func dictionarySettings() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M8_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let suite = "M8Render-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = destination.appending(path: "render-fixture")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"),
                                  vocabularyDirectory: root)
        let login = LoginItem()
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            for populated in [true, false] {
                dictation.dictionary = populated ? [
                    DictionaryEntry(term: "NanthAi", variants: ["nant", "nanth ai"]),
                    DictionaryEntry(term: "Niccolò", variants: ["nicolo"]),
                    DictionaryEntry(term: "Okafor", variants: ["oka for"])
                ] : []
                try await render(SettingsPane(tab: .dictionary, dictation: dictation, loginItem: login)
                    .frame(width: 600, height: 440).environment(\.colorScheme, scheme),
                    to: destination.appending(path: "mac-dictionary-\(populated ? "populated" : "empty")-\(appearance).png"))
            }
        }
        dictation.dictionary = [DictionaryEntry(term: "  "), DictionaryEntry(term: "NanthAi")]
        let controller = NSHostingController(rootView: SettingsView(dictation: dictation, showOnboarding: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.close()
        #expect(dictation.dictionary.map(\.term) == ["NanthAi"])
    }

    private func render(_ view: some View, to url: URL) async throws {
        // ImageRenderer omits AppKit-backed controls (Form and TextField). Rasterize
        // their real native hosting view first, then export that image with ImageRenderer.
        let controller = NSHostingController(rootView: view.environment(\.appearsActive, true))
        let host = controller.view
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let capture = host
        let nativeBitmap = try #require(capture.bitmapImageRepForCachingDisplay(in: capture.bounds))
        capture.cacheDisplay(in: capture.bounds, to: nativeBitmap)
        let captureSize = capture.bounds.size
        let snapshot = NSImage(size: captureSize)
        snapshot.addRepresentation(nativeBitmap)
        let renderer = ImageRenderer(content: Image(nsImage: snapshot).frame(width: captureSize.width, height: captureSize.height))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        window.close()
    }
}
