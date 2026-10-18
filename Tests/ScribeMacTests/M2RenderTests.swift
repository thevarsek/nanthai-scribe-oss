import AppKit
import ScribeCore
import ScribeMacCore
import SwiftUI
import Testing
@testable import ScribeMac

/// Opt-in visual fixtures. No hotkey tap, audio capture, asset fetching, or login registration.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M2_RENDER_DIR"] != nil))
struct M2RenderTests {
    @Test func renderSettingsAndOnboarding() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M2_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let icon: NSImage? = NSImage(contentsOf: root.appending(path: "Resources/AppIcon.icns"))
        let loadedIcon = try #require(icon)
        NSApp.applicationIconImage = loadedIcon
        let domain = "ScribeM2Renders-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(["en_GB", "it_IT"], forKey: "languages")
        let dictation = Dictation(defaults: defaults, historyURL: destination.appending(path: "fixture-history.json"),
                                  availableLanguages: ["en_GB", "it_IT", "de_DE", "en_US", "es_ES", "fr_FR"]
                                    .map(Locale.init(identifier:)), vocabularyDirectory: destination.appending(path: "fixture-vocabulary"))
        dictation.tone = .casual
        dictation.snippets = [Snippet(trigger: "my signature", text: "Best regards,\nAlex"),
                              Snippet(trigger: "studio address", text: "12 Orchard Street\nLondon")]
        let login = LoginItem()
        let bundle = try #require(Bundle(url: root.appending(path: "build/NanthAi Scribe.app")))
        let requestedTabs = ProcessInfo.processInfo.environment["SCRIBE_M2_RENDER_TABS"]?.split(separator: ",").map(String.init)
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .light ? "light" : "dark"
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            for tab in SettingsTab.allCases where requestedTabs?.contains(tab.rawValue) ?? true {
                try await render(SettingsPane(tab: tab, dictation: dictation, loginItem: login, bundle: bundle)
                    .frame(width: 600, height: 440).environment(\.colorScheme, scheme),
                           to: destination.appending(path: "settings-\(tab.rawValue)-\(appearance).png"))
            }
            if requestedTabs != nil { continue }
            dictation.engine = .gemma
            try await render(SettingsPane(tab: .polish, dictation: dictation, loginItem: login, bundle: bundle)
                .frame(width: 600, height: 440).environment(\.colorScheme, scheme),
                       to: destination.appending(path: "settings-polish-gemma-\(appearance).png"))
            dictation.engine = .apple
            for step in OnboardingStep.allCases {
                try await render(OnboardingPage(step: step, talkShortcut: .rightOption).environment(\.colorScheme, scheme),
                           to: destination.appending(path: "onboarding-\(step.rawValue + 1)-\(appearance).png"))
            }
            for step in [OnboardingStep.accessibility, .microphone] {
                try await render(OnboardingPage(step: step, talkShortcut: .rightOption,
                                          accessibilityGranted: true, microphoneGranted: true)
                    .environment(\.colorScheme, scheme),
                           to: destination.appending(path: "onboarding-\(step.rawValue + 1)-granted-\(appearance).png"))
            }
        }
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
