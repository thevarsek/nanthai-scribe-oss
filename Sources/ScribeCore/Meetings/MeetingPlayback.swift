import AVFoundation
import Observation

/// Multiple capture streams share the meeting clock, including gaps and restarted segments.
@MainActor @Observable
public final class MeetingPlayback {
    public private(set) var position = 0.0
    public private(set) var duration = 0.0
    public private(set) var isPlaying = false
    public private(set) var speed: Float = 1
    public private(set) var error: String?
    public var hasAudio: Bool { !sources.isEmpty }
    private struct Source { let player: AVAudioPlayer; let offset: Double }
    /// Session configuration belongs to the platform adapter, keeping the shared clock platform-neutral.
    @ObservationIgnored public var preparePlayback: @MainActor () throws -> Void = {}
    private var sources: [Source] = []
    private var ticker: Task<Void, Never>?
    private var anchor: ContinuousClock.Instant?
    private var anchorPosition = 0.0
    public init() {}
    public func load(_ meeting: Meeting, folder: URL) {
        stop(); sources = []; duration = 0; position = 0
        for segment in meeting.audio {
            guard let player = try? AVAudioPlayer(contentsOf: folder.appending(path: segment.file)) else { continue }
            player.enableRate = true; player.prepareToPlay()
            sources.append(Source(player: player, offset: segment.offset))
            duration = max(duration, segment.offset + player.duration)
        }
    }
    public func toggle() { if isPlaying { pause() } else { play() } }
    public func play() {
        guard hasAudio else { return }
        error = nil
        do { try preparePlayback() }
        catch { self.error = "Couldn't play this recording."; return }
        if position >= duration { position = 0 }
        isPlaying = true; anchor = .now; anchorPosition = position
        synchronize()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.isPlaying, let anchor = self.anchor else { return }
                let elapsed = anchor.duration(to: .now).components
                self.position = min(self.duration, self.anchorPosition + (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * Double(self.speed))
                if self.position >= self.duration { self.pause(); return }
                self.synchronize()
            }
        }
    }
    public func pause() { isPlaying = false; ticker?.cancel(); ticker = nil; for source in sources { source.player.pause() } }
    public func stop() { pause(); position = 0 }
    public func seek(_ seconds: Double) {
        position = min(duration, max(0, seconds.isFinite ? seconds : 0))
        anchor = .now; anchorPosition = position
        for source in sources { source.player.pause(); source.player.currentTime = max(0, position - source.offset) }
        synchronize()
    }
    public func cycleSpeed() { speed = speed == 1 ? 1.5 : speed == 1.5 ? 2 : 1; seek(position) }
    public func isActive(_ turn: MeetingTurn) -> Bool { isPlaying && position >= turn.start && position < turn.end }
    private func synchronize() {
        for source in sources {
            let local = position - source.offset
            if isPlaying && local >= 0 && local < source.player.duration {
                source.player.rate = speed
                if !source.player.isPlaying { source.player.currentTime = local; source.player.play() }
            } else { source.player.pause() }
        }
    }
    #if DEBUG
    public func preview(position: Double, playing: Bool, duration: Double) {
        self.position = position; self.isPlaying = playing; self.duration = duration
    }
    #endif
}
