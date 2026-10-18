import AppKit
import ScribeUI
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M87_RENDER_DIR"] != nil))
struct M87RenderTests {
    #if DEBUG
    @Test func hudRevealFrames() async throws {
        let root = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M87_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let domain = "M87Renders-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let fixture = root.appending(path: "fixture")
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: fixture)
        }
        let dictation = Dictation(defaults: defaults, historyURL: fixture.appending(path: "history.json"),
                                  availableLanguages: [], vocabularyDirectory: fixture)
        let prefix = "Let's meet tomorrow at ten."
        let tail = "Please bring the project notes and the revised schedule so we can review the details together."
        for reduced in [false, true] {
            dictation.previewLiveText(prefix, volatile: "")
            let host = NSHostingView(rootView: HUDView(dictation: dictation, reduceMotion: reduced)
                .frame(width: 500, height: 224))
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 500, height: 224),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            let variant = reduced ? "reduce-motion" : "motion"
            try capture(host, to: root.appending(path: "mac-hud-\(variant)-baseline.png"))
            dictation.previewLiveText(prefix + " " + tail, volatile: tail)
            for frame in 0..<6 {
                try await Task.sleep(for: .milliseconds(60))
                try capture(host, to: root.appending(path: "mac-hud-\(variant)-\(frame).png"))
            }
            try await Task.sleep(for: .milliseconds(600))
            dictation.previewLiveText(prefix + " " + tail, volatile: "")
            try await Task.sleep(for: .milliseconds(200))
            try capture(host, to: root.appending(path: "mac-hud-\(variant)-final.png"))
            window.close()
        }
    }
    #endif

    private func capture(_ host: NSView, to url: URL) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
