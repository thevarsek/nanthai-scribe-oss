import Foundation

/// Recording time excludes pauses, including interruptions, so segment offsets and the cap agree.
public struct MeetingCaptureClock: Sendable, Equatable {
    public enum State: Sendable { case idle, recording, paused, stopped }
    public private(set) var state: State = .idle
    private var started: Date?
    private var pausedAt: Date?
    private var pausedSeconds = 0.0
    private var stoppedAt: Date?
    private var interruptedRecording = false
    public init() {}
    public func elapsed(at now: Date) -> Double {
        guard let started else { return 0 }
        return max(0, (pausedAt ?? stoppedAt ?? now).timeIntervalSince(started) - pausedSeconds)
    }
    public mutating func start(at now: Date) {
        guard state == .idle else { return }
        started = now; state = .recording
    }
    public mutating func pause(at now: Date) {
        guard state == .recording else { return }
        pausedAt = now; state = .paused
    }
    public mutating func resume(at now: Date) {
        guard state == .paused else { return }
        pausedSeconds += now.timeIntervalSince(pausedAt ?? now)
        pausedAt = nil; state = .recording
    }
    public mutating func stop(at now: Date) {
        guard state == .recording || state == .paused else { return }
        stoppedAt = pausedAt ?? now; state = .stopped
    }
    public mutating func interruptionBegan(at now: Date) {
        interruptedRecording = state == .recording
        pause(at: now)
    }
    @discardableResult public mutating func interruptionEnded(shouldResume: Bool, at now: Date) -> Bool {
        let resumeRecording = interruptedRecording && shouldResume && state == .paused
        interruptedRecording = false
        if resumeRecording { resume(at: now) }
        return resumeRecording
    }
}

public enum MeetingCapturePolicy {
    public static let minimumFreeBytes: Int64 = 1_000_000_000
    public static let maximumSeconds = 4.0 * 60 * 60
    public static let warningSeconds = maximumSeconds - 10 * 60
    // Reserve enough space to close the PCM and persist the meeting before storage is exhausted.
    public static let stopFreeBytes: Int64 = 100_000_000
    public static func canStart(freeBytes: Int64) -> Bool { freeBytes >= minimumFreeBytes }
    public static func shouldStop(elapsed: Double, battery: Float, freeBytes: Int64) -> Bool {
        elapsed >= maximumSeconds || (battery >= 0 && battery <= 0.05) || freeBytes <= stopFreeBytes
    }
}
