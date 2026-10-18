import AppKit
import CoreFoundation
import SwiftUI
import Testing
@testable import ScribeMac
@testable import ScribeUI

/// Streams a recogniser-shaped transcript through the real HUD: 10 Hz updates that grow past
/// 400 words, revise the last words, finalize in chunks, and carry level updates like the mic.
/// Synthetic words only; the test prints timings, never text.
@MainActor
@Suite(.serialized)
struct M87cRevealPerformanceTests {
    @Test func modelUpdateStaysCheapAtFourHundredWords() {
        var stream = TranscriptStream()
        var state = RevealState()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var samples: [Double] = []
        for _ in 0..<300 {
            let update = stream.next()
            now.addTimeInterval(0.1)
            let clock = Self.threadCPUMilliseconds()
            state = state.updating(.init(text: update.text, volatileTail: update.volatile), at: now, reduceMotion: false)
            samples.append(Self.threadCPUMilliseconds() - clock)
        }
        samples.sort()
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        print("M87c RevealState.updating CPU ms at \(stream.wordCount) words: p50=\(samples[samples.count / 2]) p95=\(p95) max=\(samples.last!)")
        #expect(p95 < 1.0)
        #expect(samples.last! < 16.7)
    }

    #if DEBUG
    @Test func hudFramesStayUnderOneFrameWhileStreaming() async throws {
        _ = NSApplication.shared
        let suite = "M87cPerformance-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"),
                                  availableLanguages: [], vocabularyDirectory: root)
        var stream = TranscriptStream()
        let first = stream.next()
        dictation.previewLiveText(first.text, volatile: first.volatile)
        // Same panel configuration as HUDController, parked offscreen.
        let window = HUDController.makePanel(dictation: dictation, reduceMotion: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let meter = StreamFrameMeter()
        meter.start()
        var level: Float = 0.3
        for tick in 0..<400 {
            // Alternate 10 Hz transcript updates with ~12 Hz mic level updates.
            if tick % 2 == 0 {
                let update = stream.next()
                meter.markUpdate(tick)
                dictation.previewLiveText(update.text, volatile: update.volatile)
            } else {
                level = level > 0.5 ? 0.3 : level + 0.07
                dictation.previewLevel(level)
            }
            try await Task.sleep(for: .milliseconds(42))
        }
        let report = meter.finish()
        _ = try #require(report.updates.count > 100)
        let updates = report.updates.map(\.cpuMs).sorted()
        let wall = report.updates.map(\.wallMs).sorted()
        let p95 = updates[Int(Double(updates.count) * 0.95)]
        let worst = report.all.sorted { $0.cpuMs > $1.cpuMs }.prefix(5).map { "\(Int($0.cpuMs * 100) / 100)ms@\($0.tick)" }
        print("M87c Mac HUD update passes CPU ms at \(stream.wordCount) words: p50=\(updates[updates.count / 2]) p95=\(p95) max=\(updates.last!) passes=\(report.all.count) worst=\(worst)")
        let others = report.all.filter { !$0.update }.map(\.cpuMs).sorted()
        print("M87c Mac HUD other passes CPU ms: p50=\(others[others.count / 2]) p95=\(others[Int(Double(others.count) * 0.95)]) max=\(others.last!)")
        print("M87c Mac HUD update passes wall ms: p50=\(wall[wall.count / 2]) p95=\(wall[Int(Double(wall.count) * 0.95)]) max=\(wall.last!)")
        // Main-thread CPU time is what the HUD costs; wall time also counts the rest of a
        // shared machine, so it is reported but not gated. One frame at 60 Hz is the limit.
        #expect(p95 < 16.7)
        #expect(report.all.map(\.cpuMs).max()! < 16.7)
    }
    #endif

    nonisolated fileprivate static func threadCPUMilliseconds() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e6
    }

}

/// Deterministic partial-transcript generator: each update revises up to two of the last
/// words, appends one to three, keeps a volatile tail of a few words and finalizes in bursts.
struct TranscriptStream {
    private static let vocabulary = [
        "meeting", "tomorrow", "project", "notes", "schedule", "review", "details", "together",
        "please", "bring", "revised", "morning", "customer", "update", "quarter", "budget",
        "design", "release", "feedback", "summary", "pipeline", "launch", "metrics", "team",
    ]
    private var words: [String] = []
    private var volatileCount = 0
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var tick = 0

    var wordCount: Int { words.count }

    mutating func next() -> (text: String, volatile: String) {
        tick += 1
        let revised = min(volatileCount, Int(random() % 3))
        words.removeLast(revised)
        volatileCount -= revised
        let appended = 2 + Int(random() % 3)
        for _ in 0..<appended {
            var word = Self.vocabulary[Int(random() % UInt64(Self.vocabulary.count))]
            if random() % 9 == 0 { word += "." }
            words.append(word)
        }
        volatileCount += appended
        if tick % 20 == 0 { volatileCount = min(volatileCount, 2) }
        volatileCount = min(volatileCount, 8)
        let text = words.joined(separator: " ")
        let volatile = words.suffix(volatileCount).joined(separator: " ")
        return (text, volatile)
    }

    private mutating func random() -> UInt64 {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return seed
    }
}

/// Main-run-loop busy intervals include layout and drawing, without bitmap readback.
/// Both observers execute on the main run loop; their storage never crosses threads.
final class StreamFrameMeter: @unchecked Sendable {
    struct Sample { let cpuMs: Double; let wallMs: Double; let tick: Int; let update: Bool }
    private var observers: [CFRunLoopObserver] = []
    private var started: (wall: ContinuousClock.Instant, cpu: Double)?
    private var samples: [Sample] = []
    private var tick = 0
    private var pendingUpdate = false

    /// Tags the current run-loop pass, which commits the transcript update that follows.
    func markUpdate(_ tick: Int) {
        self.tick = tick
        pendingUpdate = true
    }

    func start() {
        let begin = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { [weak self] _, _ in
            self?.started = (.now, M87cRevealPerformanceTests.threadCPUMilliseconds())
        }!
        let end = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [weak self] _, _ in
            guard let self, let started = self.started else { return }
            let duration = started.wall.duration(to: .now).components
            let wallMs = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            let cpuMs = M87cRevealPerformanceTests.threadCPUMilliseconds() - started.cpu
            self.samples.append(Sample(cpuMs: cpuMs, wallMs: wallMs, tick: self.tick, update: self.pendingUpdate))
            self.pendingUpdate = false
            self.started = nil
        }!
        observers = [begin, end]
        for observer in observers { CFRunLoopAddObserver(CFRunLoopGetMain(), observer, CFRunLoopMode.commonModes) }
    }

    func finish() -> (all: [Sample], updates: [Sample]) {
        for observer in observers { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, CFRunLoopMode.commonModes) }
        observers = []
        return (samples, samples.filter(\.update))
    }
}
