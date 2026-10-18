import AppKit
import AVFoundation
import ScribeCore

/// Owns a meeting's audio sources for the length of one recording. Every interruption
/// (input device change, default output change, sleep) closes the current files and opens
/// new segments, so a recording survives AirPods connecting or a lid closing; the finish
/// pipeline concatenates segments by their offsets.
@MainActor
final class MeetingCaptureSession {
    enum Health: Equatable { case healthy, failed(String) }
    /// Seconds without microphone frames before a restart is attempted, then before giving up.
    static let stallRestartTicks = 5
    static let stallFailureTicks = 12

    let folder: URL
    let anchor = AVAudioTime.seconds(forHostTime: mach_absolute_time())
    private(set) var segments: [MeetingAudioSegment] = []
    private(set) var health: Health = .healthy
    private(set) var restarts = 0
    /// Fires after segment changes so the recorder can persist them before any crash.
    var onChange: (() -> Void)?
    private let sources: [(stream: String, source: any MeetingAudioSource)]
    private var counts: [String: Int] = [:]
    private var open: [String: Int] = [:]
    private var lastMicrophoneFrames: Int64 = 0
    private var stalledTicks = 0
    private var sleeping = false
    private(set) var paused = false
    private var pausedAt: Double?
    private var pausedDuration = 0.0
    private var changing = false
    private var stopped = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var reconnecting: Set<String> = []
    private var flowed: Set<String> = []
    private var failures: Set<String> = []
    private var sampledFrames: [String: Int64] = [:]
    private var lastFramesAt: [String: Double] = [:]
    private var stoppedAt: Double?
    private var captureErrors: [String] = []
    private var observers: [NSObjectProtocol] = []

    var elapsed: Double { max(0, (pausedAt ?? stoppedAt ?? now) - anchor - pausedDuration) }

    /// Samples are polled by the UI at ten Hz; silence on the call stream is normal until a voice arrives.
    func sourceHealth(_ stream: String) async -> MeetingSourceHealth {
        if paused { return .paused }
        if reconnecting.contains(stream) || sleeping { return .warning("Reconnecting…") }
        if failures.contains(stream) { return .warning("Not coming through") }
        guard let source = source(stream) else { return .warning("Not coming through") }
        let frames = await source.frames, level = await source.level
        let previous = sampledFrames[stream] ?? 0
        sampledFrames[stream] = frames
        if frames > previous { lastFramesAt[stream] = now }
        if await source.hasSignal { flowed.insert(stream) }
        if stream == MeetingAudioSegment.system && !flowed.contains(stream) { return .none }
        if frames == 0 || now - (lastFramesAt[stream] ?? anchor) > 0.5 { return .warning("Not coming through") }
        return .level(level)
    }

    func pause() async {
        await lock(); defer { unlock() }
        guard !paused, !stopped else { return }
        pausedAt = now; paused = true
        for (stream, _) in sources { await closeSegment(stream) }
    }
    func resume() async {
        await lock(); defer { unlock() }
        guard paused, !stopped else { return }
        pausedDuration += now - (pausedAt ?? now)
        pausedAt = nil; paused = false; stalledTicks = 0
        guard !sleeping, health == .healthy else { return }
        for (stream, _) in sources {
            do { try await openSegment(stream) } catch { failures.insert(stream); health = .failed(error.localizedDescription) }
        }
    }

    // Source operations suspend across actors; serialize them so Stop cannot race a device restart or Resume.
    private func lock() async {
        if changing { await withCheckedContinuation { waiters.append($0) } }
        changing = true
    }
    private func unlock() {
        if waiters.isEmpty { changing = false } else { waiters.removeFirst().resume() }
    }

    /// - Parameter sources: started in order; system audio first so its permission prompt precedes the microphone.
    init(folder: URL, sources: [(stream: String, source: any MeetingAudioSource)]) {
        self.folder = folder; self.sources = sources
    }

    func start() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (stream, _) in sources { try await openSegment(stream) }
        for (stream, source) in sources {
            await source.observeInterruptions { [weak self] in
                Task { @MainActor in await self?.restart(stream) }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.sleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.wake() }
            },
        ]
    }

    /// Reopens one stream in a new file; failure is terminal for the session.
    func restart(_ stream: String) async {
        await lock(); defer { unlock() }
        guard health == .healthy, !sleeping, !paused, !stopped, sources.contains(where: { $0.stream == stream }) else { return }
        reconnecting.insert(stream)
        defer { reconnecting.remove(stream) }
        restarts += 1
        await closeSegment(stream)
        do { try await openSegment(stream) } catch { failures.insert(stream); health = .failed(error.localizedDescription) }
    }

    /// Called once a second. Microphone silence still delivers frames, so a stall means the
    /// device went away without a configuration change (typical after sleep).
    func checkProgress() async {
        guard health == .healthy, !sleeping, !paused, !stopped, let mic = source(MeetingAudioSegment.microphone) else { return }
        let frames = await mic.frames
        guard health == .healthy, !sleeping, !paused, !stopped else { return }
        if frames > lastMicrophoneFrames { lastMicrophoneFrames = frames; stalledTicks = 0; return }
        stalledTicks += 1
        if stalledTicks == Self.stallRestartTicks { await restart(MeetingAudioSegment.microphone) }
        else if stalledTicks >= Self.stallFailureTicks {
            failures.insert(MeetingAudioSegment.microphone)
            health = .failed(MeetingCaptureError.microphoneStalled.localizedDescription)
        }
    }

    /// Closes every file and releases the sources. Returns capture problems worth showing.
    func stop() async -> [String] {
        await lock(); defer { unlock() }
        guard !stopped else { return captureErrors }
        stopped = true; stoppedAt = now
        for (stream, _) in sources { await closeSegment(stream) }
        var errors = captureErrors
        for (_, source) in sources { await source.release() }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        if case .failed(let message) = health { errors.append(message) }
        if segments.isEmpty { errors.append(MeetingCaptureError.noAudio.localizedDescription) }
        return errors
    }

    private func sleep() async {
        await lock(); defer { unlock() }
        guard !sleeping, !stopped else { return }
        sleeping = true
        for (stream, _) in sources { await closeSegment(stream) }
    }
    private func wake() async {
        await lock(); defer { unlock() }
        guard sleeping, !stopped else { return }
        sleeping = false
        guard health == .healthy, !paused else { return }
        stalledTicks = 0
        for (stream, _) in sources {
            do { try await openSegment(stream) } catch { failures.insert(stream); health = .failed(error.localizedDescription) }
        }
    }

    private func source(_ stream: String) -> (any MeetingAudioSource)? { sources.first { $0.stream == stream }?.source }

    private func openSegment(_ stream: String) async throws {
        guard let source = source(stream) else { return }
        let index = (counts[stream] ?? 0) + 1
        counts[stream] = index
        let name = stream == MeetingAudioSegment.microphone ? "microphone" : "system"
        let segment = MeetingAudioSegment(stream: stream, file: "\(name)-\(index).caf", offset: elapsed)
        try await source.start(url: folder.appending(path: segment.file))
        segments.append(segment)
        open[stream] = segments.count - 1
        sampledFrames[stream] = 0
        if stream == MeetingAudioSegment.microphone { lastMicrophoneFrames = 0 }
        onChange?()
    }

    /// Fixes the segment's offset from its first buffer and drops files that never received audio.
    @discardableResult
    private func closeSegment(_ stream: String) async -> String? {
        guard let source = source(stream), let index = open[stream] else { return nil }
        open[stream] = nil
        if await source.hasSignal { flowed.insert(stream) }
        if let first = await source.firstHostTime { segments[index].offset = max(0, first - anchor - pausedDuration) }
        var error: String?
        do { try await source.stop() } catch let failure { error = failure.localizedDescription; captureErrors.append(failure.localizedDescription) }
        if await source.frames == 0, !MeetingAudioFiles.hasAudio(folder.appending(path: segments[index].file)) {
            try? FileManager.default.removeItem(at: folder.appending(path: segments[index].file))
            segments.remove(at: index)
            for (key, value) in open where value > index { open[key] = value - 1 }
        }
        onChange?()
        return error
    }

    private var now: Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }
}


enum MeetingSourceHealth: Equatable {
    case level(Double), warning(String), none, paused
}
