import os

/// Key-down → first-words latency for one utterance. Durations only: never transcript text.
@MainActor
final class CaptureTiming {
    enum Stage: String { case micRunning, transcriberReady, firstResult }

    var keyDown: ContinuousClock.Instant?
    private var seen: Set<Stage> = []
    private static let logger = Logger(subsystem: "tech.nanthai.Scribe", category: "Latency")

    func mark(_ stage: Stage) {
        guard let keyDown, seen.insert(stage).inserted else { return }
        let ms = Self.milliseconds(from: keyDown, to: .now)
        Self.logger.info("keyDown→\(stage.rawValue, privacy: .public): \(ms, privacy: .public) ms")
    }

    nonisolated static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
        let parts = (end - start).components
        return Int(parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000)
    }
}
