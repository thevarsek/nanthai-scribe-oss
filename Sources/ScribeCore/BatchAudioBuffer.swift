import AVFoundation
import Foundation

/// A persistent converter preserves resampling state across microphone buffers.
/// Accessed only by LiveTranscriber's single input-forwarding task.
@MainActor
final class BatchAudioBuffer {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private(set) var samples: [Float] = []

    init(inputFormat: AVAudioFormat, sampleRate: Double) throws {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output) else {
            throw ScribeError.noAudioFormat
        }
        self.outputFormat = output
        self.converter = converter
    }

    func append(_ buffer: AVAudioPCMBuffer) throws { try convert(buffer) }
    func finish() throws { try convert(nil) }

    private func convert(_ input: AVAudioPCMBuffer?) throws {
        let feeder = ConverterFeeder(input)
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
                throw ScribeError.noAudioFormat
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                feeder.next(state)
            }
            if let error { throw error }
            if let channel = output.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            switch status {
            case .haveData: continue
            case .inputRanDry, .endOfStream: return
            case .error: throw ScribeError.noAudioFormat
            @unknown default: throw ScribeError.noAudioFormat
            }
        }
    }
}

/// AVAudioConverter invokes this synchronously, on the single caller's thread.
private final class ConverterFeeder: @unchecked Sendable {
    private var input: AVAudioPCMBuffer?
    private let endOfStream: Bool
    init(_ input: AVAudioPCMBuffer?) { self.input = input; endOfStream = input == nil }
    func next(_ state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let input else { state.pointee = endOfStream ? .endOfStream : .noDataNow; return nil }
        self.input = nil
        state.pointee = .haveData
        return input
    }
}
