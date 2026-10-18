import AppKit
import ScribeCore
import ScribeUI
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M9_RENDER_DIR"] != nil))
struct M9RenderTests {
    @Test func render() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M9_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let domain = "M9-render-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let root = destination.appending(path: "fixture")
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        dictation.dictionary = [DictionaryEntry(term: "NanthAi", variants: ["Nantai"], source: .learned)]
        let pair = CorrectionPair(heard: "nicolo", meant: "Niccolò")
        for _ in 0..<3 { _ = dictation.learning.record(pair, canAsk: false) }
        let ignored = CorrectionPair(heard: "oka for", meant: "Okafor")
        _ = dictation.learning.record(ignored, canAsk: false)
        dictation.learning.ignore(ignored)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            try await save(Form {
                DictionarySettings(vocabulary: dictation.vocabulary, learning: dictation.learning, contacts: dictation.contacts)
            }.formStyle(.grouped).tint(Brand.coral).frame(width: 600, height: 780).environment(\.colorScheme, scheme),
                to: destination.appending(path: "mac-dictionary-\(name).png"))
            dictation.previewCorrection(CorrectionPair(heard: "Nantai", meant: "NanthAi"))
            try await save(HUDView(dictation: dictation).frame(width: 500, height: 160).environment(\.colorScheme, scheme),
                to: destination.appending(path: "mac-hud-prompt-\(name).png"))
            dictation.previewCorrection(nil, added: true)
            try await save(HUDView(dictation: dictation).frame(width: 500, height: 160).environment(\.colorScheme, scheme),
                to: destination.appending(path: "mac-hud-added-\(name).png"))
            dictation.previewCorrection(nil)
            for enabled in [false, true] {
                dictation.contacts.previewEnabled(enabled)
                try await save(Form { ContactsNamesSection(contacts: dictation.contacts) }.formStyle(.grouped)
                    .frame(width: 600, height: 180).environment(\.colorScheme, scheme),
                    to: destination.appending(path: "mac-contacts-\(enabled ? "on" : "off")-\(name).png"))
            }
            dictation.contacts.previewEnabled(false)
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
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let native = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: native)
        let image = NSImage(size: size)
        image.addRepresentation(native)
        let renderer = ImageRenderer(content: Image(nsImage: image).frame(width: size.width, height: size.height))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }
}
