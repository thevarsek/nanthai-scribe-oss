import Foundation

public enum DictationFailure {
    public static let edit = "Couldn't edit. Your text is unchanged."
    public static let refine = "Refine didn't finish. Your words were inserted as spoken."
    public static func shouldInsert(editing: Bool, rewriteFailed: Bool) -> Bool { !editing || !rewriteFailed }
    public static func rewrite(_ error: any Error, editing: Bool) -> String { editing ? edit : refine }
    public static func microphoneDenied(onPhone: Bool) -> String {
        "Microphone access is off. Turn it on in \(onPhone ? "Settings" : "System Settings") › Privacy & Security › Microphone."
    }
}

public enum FinishDeadline {
    public static func seconds(audioLength: TimeInterval) -> TimeInterval {
        max(10, audioLength.isFinite ? max(0, audioLength) * 0.5 : 10)
    }

    /// An uncooperative Speech/model teardown must not hold the fallback behind task-group exit.
    @MainActor public static func wait<Value: Sendable>(seconds: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Value,
        fallback: @escaping @MainActor @Sendable () -> Value) async -> Value {
        let delivery = Delivery<Value>()
        return await withCheckedContinuation { continuation in
            delivery.continuation = continuation
            let work = Task { delivery.finish(await operation()) }
            let timer = Task {
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard delivery.continuation != nil else { return }
                work.cancel()
                delivery.finish(fallback())
            }
            delivery.timer = timer
        }
    }
    @MainActor private final class Delivery<Value: Sendable> {
        var continuation: CheckedContinuation<Value, Never>?
        var timer: Task<Void, Never>?
        func finish(_ value: Value) {
            guard let continuation else { return }
            self.continuation = nil
            timer?.cancel(); timer = nil
            continuation.resume(returning: value)
        }
    }
}

/// Uses the same normalized microphone energy as the waveform, independent of recognizer output.
public struct SpeechDetector: Sendable {
    public private(set) var lastSpeechAt: Date?
    public init() {}
    public mutating func observe(level: Float, at now: Date = .now) {
        if level >= 0.2 { lastSpeechAt = now }
    }
    public func isInactive(startedAt: Date?, now: Date = .now) -> Bool {
        guard let last = lastSpeechAt ?? startedAt else { return false }
        return now.timeIntervalSince(last) >= 600
    }
}

public struct LastDictationRecovery: Codable, Equatable, Sendable {
    public var text: String
    public var createdAt: Date
    public init(text: String, createdAt: Date = .now) { self.text = text; self.createdAt = createdAt }
    public func isExpired(at now: Date = .now) -> Bool { now.timeIntervalSince(createdAt) >= 3_600 }
}

public struct SaveFailure: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let message: String
    public init(_ message: String) { id = UUID(); self.message = message }
}
