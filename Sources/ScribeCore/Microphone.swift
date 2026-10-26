import AVFoundation
import Speech

/// Captures the default input and converts it to the speech analyzer's format.
///
/// Every buffer handed out is freshly allocated: `AVAudioEngine` reuses its tap buffer as
/// soon as the callback returns, so passing it on would corrupt audio downstream.
public final class Microphone: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var running = false
    private var route: MicrophoneRoute?
    /// Upper bound on audio held before an analyzer is attached.
    public static let prerollLimit: Double = 30

    public init() {}

    public static func requestAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Whether recording is already allowed, so capture can begin without an async prompt.
    public static var accessGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }

    /// Opens the input and keeps its audio in memory until `attach` supplies the analyzer's format.
    ///
    /// Speech setup can take seconds on a cold start; capturing first means nothing said in
    /// the meantime is lost. The buffer is capped at `Microphone.prerollLimit` seconds.
    /// - Parameter onLevel: 0…1 loudness per buffer, for a waveform. Called on the audio thread.
    public func startCapture(onLevel: @escaping @Sendable (Float) -> Void) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        #endif

        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard source.sampleRate > 0 else { throw ScribeError.microphoneUnavailable }
        let route = MicrophoneRoute(onLevel: onLevel)
        self.route = route
        node.installTap(onBus: 0, bufferSize: 4096, format: source, block: Self.tap(route))

        engine.prepare()
        do {
            try engine.start()
            running = true
        } catch {
            node.removeTap(onBus: 0)
            self.route = nil
            throw error
        }
    }

    /// Converts everything captured so far, in order, then continues live into `sink`.
    /// No buffer is dropped or repeated across the hand-over.
    public func attach(
        format target: AVAudioFormat,
        sink: AsyncStream<AnalyzerInput>.Continuation,
        formatChanged: (@Sendable (String) -> Void)? = nil
    ) {
        route?.attach(target: target, sink: sink, formatChanged: formatChanged)
    }

    /// Seconds of audio captured but not yet handed to an analyzer.
    public var bufferedSeconds: Double { route?.bufferedSeconds ?? 0 }
    /// Loudest `onLevel` value seen since capture began; lets callers tell speech from silence.
    public var peakLevel: Float { route?.peakLevel ?? 0 }

    /// - Parameters:
    ///   - sink: receives converted audio, in capture order.
    ///   - onLevel: 0…1 loudness per buffer, for a waveform. Called on the audio thread.
    public func start(
        format target: AVAudioFormat,
        sink: AsyncStream<AnalyzerInput>.Continuation,
        formatChanged: (@Sendable (String) -> Void)? = nil,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        try startCapture(onLevel: onLevel)
        attach(format: target, sink: sink, formatChanged: formatChanged)
    }

    public func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        route = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private nonisolated static func tap(_ route: MicrophoneRoute) -> AVAudioNodeTapBlock {
        { buffer, _ in route.receive(buffer) }
    }

    /// RMS mapped onto a perceptual-ish 0…1 range.
    fileprivate static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        return max(0, min(1, (db + 55) / 45))
    }
}

/// Converters follow the buffers' actual format, including device route changes.
///
/// Until a target is attached, buffers are copied into a bounded pre-roll queue. `attach`
/// drains it and goes live under the same lock the tap takes, which is what keeps the
/// audio ordered and unduplicated.
final class MicrophoneRoute: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var target: AVAudioFormat?
    private var sink: AsyncStream<AnalyzerInput>.Continuation?
    private var formatChanged: (@Sendable (String) -> Void)?
    private let onLevel: @Sendable (Float) -> Void
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingSeconds = 0.0
    private var peak: Float = 0

    init(onLevel: @escaping @Sendable (Float) -> Void) { self.onLevel = onLevel }

    var bufferedSeconds: Double { lock.withLock { pendingSeconds } }
    var peakLevel: Float { lock.withLock { peak } }

    func attach(target: AVAudioFormat, sink: AsyncStream<AnalyzerInput>.Continuation,
                formatChanged: (@Sendable (String) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        self.target = target
        self.sink = sink
        self.formatChanged = formatChanged
        let queued = pending
        pending = []
        pendingSeconds = 0
        for buffer in queued { convertAndYield(buffer) }
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        let level = Microphone.level(of: buffer)
        onLevel(level)
        lock.lock()
        defer { lock.unlock() }
        peak = max(peak, level)
        if sink != nil {
            convertAndYield(buffer)
        } else if let copy = Self.copy(of: buffer) {
            pending.append(copy)
            pendingSeconds += Double(copy.frameLength) / copy.format.sampleRate
            while pendingSeconds > Microphone.prerollLimit, pending.count > 1 {
                let dropped = pending.removeFirst()
                pendingSeconds -= Double(dropped.frameLength) / dropped.format.sampleRate
            }
        }
    }

    /// Caller holds `lock`.
    private func convertAndYield(_ buffer: AVAudioPCMBuffer) {
        guard let target, let sink else { return }
        if converter?.inputFormat != buffer.format {
            converter = SpeechAudioConversion.converter(from: buffer.format, to: target, voiceProcessing: false)
            formatChanged?("source=\(buffer.format) target=\(target)")
        }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        let feeder = OneShot(buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in feeder.next(status) }
        if error == nil, output.frameLength > 0 { sink.yield(AnalyzerInput(buffer: output)) }
    }

    private static func copy(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: Int(buffer.frameLength))
            }
            return copy
        }
        return nil
    }
}

/// Hands a single buffer to `AVAudioConverter`, then reports "no data for now" so the
/// converter keeps its state for the next tap callback.
private final class OneShot: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
