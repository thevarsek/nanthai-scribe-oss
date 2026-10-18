import AppKit
import os
import CoreFoundation
import SwiftUI
import Testing
@testable import ScribeMac

/// Opt-in local diagnostics use synthetic words and emit timings only.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M161_PROFILE"] != nil))
struct M161PerformanceTests {
    #if DEBUG
    @Test func streamHUDAtTenHz() async throws {
        _ = NSApplication.shared
        let suite = "M161Performance-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"),
                                  availableLanguages: [], vocabularyDirectory: root)
        var text = String(repeating: "Synthetic project notes for tomorrow. ", count: 15)
        dictation.previewLiveText(text, volatile: "")
        let host = NSHostingView(rootView: HUDView(dictation: dictation, reduceMotion: false).frame(width: 500, height: 224))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 224),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let meter = LiveFrameMeter()
        meter.start()
        for _ in 0..<30 {
            text += " Additional words for this update."
            dictation.previewLiveText(text, volatile: "Additional words for this update.")
            try await Task.sleep(for: .milliseconds(100))
        }
        let samples = meter.finish()
        _ = try #require(!samples.isEmpty)
        print("M161 Mac HUD main-run-loop frame work ms: p50=\(samples[samples.count / 2]) p95=\(samples[Int(Double(samples.count) * 0.95)]) max=\(samples.last!) samples=\(samples.count)")
    }
    #endif
}

/// Main-run-loop busy intervals include layout and drawing, without bitmap readback.
/// Both observers execute on the main run loop; their storage never crosses threads.
private final class LiveFrameMeter: @unchecked Sendable {
    private let signposter = OSSignposter(subsystem: "tech.nanthai.Scribe.diagnostics", category: "RevealFrames")
    private var observers: [CFRunLoopObserver] = []
    private var started: ContinuousClock.Instant?
    private var interval: OSSignpostIntervalState?
    private var samples: [Double] = []

    func start() {
        let begin = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { [weak self] _, _ in
            guard let self else { return }
            self.started = .now
            self.interval = self.signposter.beginInterval("LiveWordFrame")
        }!
        let end = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [weak self] _, _ in
            guard let self, let started = self.started else { return }
            let duration = started.duration(to: .now).components
            self.samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
            if let interval = self.interval { self.signposter.endInterval("LiveWordFrame", interval) }
            self.started = nil
            self.interval = nil
        }!
        observers = [begin, end]
        for observer in observers { CFRunLoopAddObserver(CFRunLoopGetMain(), observer, CFRunLoopMode.commonModes) }
    }

    func finish() -> [Double] {
        for observer in observers { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, CFRunLoopMode.commonModes) }
        observers = []
        if let interval { signposter.endInterval("LiveWordFrame", interval) }
        interval = nil
        return samples.sorted()
    }
}
