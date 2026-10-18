import AVFoundation
import Foundation
import Synchronization

/// Copies borrowed audio before returning to Core Audio; conversion and disk writes run on a
/// serial queue. The format is immutable, counters are locked, and the file is queue-confined.
///
/// Files are 16 kHz mono 16-bit PCM in a CAF: AVAudioFile only writes AAC/ALAC packet tables
/// on close, so a killed process leaves those unreadable, whereas PCM stays decodable up to the
/// last written frame. Compression happens after a successful finish (`MeetingAudioFiles`).
public final class MeetingAudioWriter: @unchecked Sendable {
    private struct State { var error: String?; var frames: Int64 = 0; var level: Double = 0; var hasSignal = false; var firstHostTime: Double? }
    public static let sampleRate = 16_000.0
    private static var fileSettings: [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
         AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    }
    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "tech.nanthai.Scribe.meeting-audio", qos: .userInitiated)
    private var file: AVAudioFile?
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    public let format: AVAudioFormat
    public init(url: URL, format: AVAudioFormat) throws {
        self.format = format
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else { throw ScribeError.noAudioFormat }
        self.target = target; self.converter = converter
        file = try AVAudioFile(forWriting: url, settings: Self.fileSettings,
                               commonFormat: target.commonFormat, interleaved: target.isInterleaved)
    }
    public var firstHostTime: Double? { state.withLock { $0.firstHostTime } }
    public var frames: Int64 { state.withLock { $0.frames } }
    public var level: Double { state.withLock { $0.level } }
    public var hasSignal: Bool { state.withLock { $0.hasSignal } }
    public func append(_ list: UnsafePointer<AudioBufferList>, hostTime: UInt64, tapOnly: Bool = false) {
        let all = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        // A tap is appended after hardware inputs in an aggregate; never mistake a device's mic for system audio.
        let count = format.isInterleaved ? 1 : Int(format.channelCount)
        let input = tapOnly ? Array(all.suffix(count)) : Array(all)
        guard let first = input.first, format.streamDescription.pointee.mBytesPerFrame > 0 else { return }
        let frames = first.mDataByteSize / format.streamDescription.pointee.mBytesPerFrame
        guard frames > 0, let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        copy.frameLength = frames
        let output = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard output.count == input.count else { return }
        for index in input.indices {
            guard let source = input[index].mData, let destination = output[index].mData else { return }
            memcpy(destination, source, min(Int(input[index].mDataByteSize), Int(output[index].mDataByteSize)))
        }
        state.withLock {
            if $0.firstHostTime == nil { $0.firstHostTime = AVAudioTime.seconds(forHostTime: hostTime) }
        }
        let owned = OwnedAudio(copy)
        queue.async { [self] in
            do {
                let written = try write(owned.buffer)
                state.withLock { $0.frames += Int64(written) }
            } catch { state.withLock { $0.error = error.localizedDescription } }
        }
    }
    /// One persistent converter keeps resampler state continuous across callbacks; `nil` drains it.
    private func write(_ buffer: AVAudioPCMBuffer?) throws -> AVAudioFrameCount {
        let capacity = AVAudioFrameCount(Double(buffer?.frameLength ?? 0) * target.sampleRate / format.sampleRate) + 64
        let feeder = OneShotFeeder(buffer)
        var written: AVAudioFrameCount = 0
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw ScribeError.noAudioFormat }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in feeder.next(state) }
            if let error { throw error }
            if output.frameLength > 0 {
                try file?.write(from: output); written += output.frameLength
                if let samples = output.floatChannelData?[0] {
                    var squareSum = 0.0
                    for index in 0..<Int(output.frameLength) { squareSum += Double(samples[index]) * Double(samples[index]) }
                    let rms = sqrt(squareSum / Double(output.frameLength))
                    state.withLock { $0.level = rms; $0.hasSignal = $0.hasSignal || rms > 0.0001 }
                }
            }
            switch status {
            case .haveData: continue
            case .inputRanDry, .endOfStream: return written
            case .error: throw ScribeError.noAudioFormat
            @unknown default: throw ScribeError.noAudioFormat
            }
        }
    }
    /// Called only after the producer has stopped; drains every queued write and closes the CAF.
    public func finish() throws {
        queue.sync {
            if let written = try? write(nil) { state.withLock { $0.frames += Int64(written) } }
            file = nil
        }
        if let error = state.withLock({ $0.error }) { throw MeetingAudioWriteError(message: error) }
    }
}
private struct OwnedAudio: @unchecked Sendable { let buffer: AVAudioPCMBuffer; init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer } }

/// Hands one buffer to `AVAudioConverter`, then reports "no data for now" so the converter keeps its state.
private final class OneShotFeeder: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    private let endOfStream: Bool
    init(_ buffer: AVAudioPCMBuffer?) { self.buffer = buffer; endOfStream = buffer == nil }
    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else { status.pointee = endOfStream ? .endOfStream : .noDataNow; return nil }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}

private struct MeetingAudioWriteError: LocalizedError {
    let message: String
    var errorDescription: String? { "The recording couldn’t be saved: " + message }
}
