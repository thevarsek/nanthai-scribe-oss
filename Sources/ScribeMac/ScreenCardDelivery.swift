import Foundation

/// Keep the release deadline independent of recognition finalization: a late model
/// result must not sneak into the rewrite while speech is still flushing audio.
struct ScreenCardDelivery {
    var fallback: String?
    var termsFinished = false
    private(set) var deadline: ContinuousClock.Instant?
    private var readyAt: ContinuousClock.Instant?
    private var value: String?
    private var finished = false

    mutating func release(at time: ContinuousClock.Instant) {
        if deadline == nil { deadline = time.advanced(by: .milliseconds(1_500)) }
    }

    mutating func finish(_ card: String?, at time: ContinuousClock.Instant) {
        value = card
        readyAt = time
        finished = true
    }

    func shouldWait(at time: ContinuousClock.Instant) -> Bool {
        guard let deadline else { return false }
        return (!finished || !termsFinished) && time < deadline
    }

    var result: String? {
        guard let readyAt, let deadline, readyAt <= deadline else { return fallback }
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }
}
