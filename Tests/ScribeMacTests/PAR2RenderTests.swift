import AppKit
import ScribeCore
import ScreenCaptureKit
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_PAR2_RENDER_DIR"] != nil))
struct PAR2RenderTests {
    @Test func renderChangedScreens() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_PAR2_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.applicationIconImage = NSImage(contentsOfFile: "Resources/AppIcon.icns")
        let appBundle = Bundle(path: "build/NanthAi Scribe.app") ?? .main
        let suite = "PAR2-render-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let fixture = destination.appending(path: "mac-fixture")
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: fixture) }
        defaults.set(["en_GB", "it_IT"], forKey: "languages")
        defaults.set("it_IT", forKey: "outputLanguage")
        let dictation = Dictation(defaults: defaults, historyURL: fixture.appending(path: "history.json"),
            availableLanguages: [Locale(identifier: "en_GB"), Locale(identifier: "it_IT")], vocabularyDirectory: fixture,
            packLanguages: await ParakeetTranscriber.appleUnsupportedLanguages)
        let recorder = MeetingRecorder(root: fixture.appending(path: "meetings"), defaults: defaults)
        let note = dictation.createNote(text: "Let's meet tomorrow to review the revised project notes.")
        recorder.meetings = [Meeting(title: "Project review", speakers: [.init(id: "you", name: "You"), .init(id: "a", name: "Sam")],
            turns: [.init(speakerID: "a", start: 0, end: 3, text: "The launch is on Friday.")], pinned: true)]
        let navigation = LibraryNavigation()
        navigation.selection = .note(note.id)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            for tab in SettingsTab.allCases {
                try await save(SettingsPane(tab: tab, dictation: dictation, loginItem: LoginItem(), bundle: appBundle)
                    .frame(width: 600, height: tab == .about ? 650 : 600).environment(\.colorScheme, scheme),
                    to: destination.appending(path: "mac-settings-\(tab.rawValue)-\(suffix).png"))
            }
            try await save(SettingsView(dictation: dictation, showOnboarding: {})
                .environment(\.colorScheme, scheme), to: destination.appending(path: "mac-settings-order-\(suffix).png"))
            try await save(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation)
                .frame(width: 1000, height: 650).environment(\.colorScheme, scheme),
                to: destination.appending(path: "mac-library-editor-\(suffix).png"))
            try await save(MacNoteEditorView(note: note, dictation: dictation, navigation: navigation)
                .frame(width: 1100, height: 650).environment(\.colorScheme, scheme),
                to: destination.appending(path: "mac-editor-presets-\(suffix).png"))
            try await save(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation, search: "missing")
                .frame(width: 1000, height: 650).environment(\.colorScheme, scheme),
                to: destination.appending(path: "mac-search-empty-\(suffix).png"))
        }
    }

    private func save(_ view: some View, to url: URL, windowServer: Bool = true) async throws {
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
