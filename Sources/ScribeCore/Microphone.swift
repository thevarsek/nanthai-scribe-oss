import AVFoundation
import Speech

/// Captures the default input and converts it to the speech analyzer's format.
///
/// Every buffer handed out is freshly allocated: `AVAudioEngine` reuses its tap buffer as
/// soon as the callback returns, so passing it on would corrupt audio downstream.
public final class Microphone: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var running = false

    public init() {}

    public static func requestAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// - Parameters:
    ///   - sink: receives converted audio, in capture order.
    ///   - onLevel: 0…1 loudness per buffer, for a waveform. Called on the audio thread.
    public func start(
        format target: AVAudioFormat,
        sink: AsyncStream<AnalyzerInput>.Continuation,
        formatChanged: (@Sendable (String) -> Void)? = nil,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        #endif

        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard source.sampleRate > 0 else { throw ScribeError.microphoneUnavailable }
        let route = MicrophoneRoute(target: target, sink: sink, formatChanged: formatChanged, onLevel: onLevel)
        node.installTap(onBus: 0, bufferSize: 4096, format: source, block: Self.tap(route))

        engine.prepare()
        do {
            try engine.start()
            running = true
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
    }

    public func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
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
private final class MicrophoneRoute: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private let target: AVAudioFormat
    private let sink: AsyncStream<AnalyzerInput>.Continuation
    private let onLevel: @Sendable (Float) -> Void
    private let formatChanged: (@Sendable (String) -> Void)?

    init(target: AVAudioFormat, sink: AsyncStream<AnalyzerInput>.Continuation,
         formatChanged: (@Sendable (String) -> Void)?, onLevel: @escaping @Sendable (Float) -> Void) {
        self.target = target
        self.sink = sink
        self.onLevel = onLevel
        self.formatChanged = formatChanged
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        onLevel(Microphone.level(of: buffer))
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
