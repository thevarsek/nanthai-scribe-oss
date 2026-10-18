import AVFoundation
import Foundation

/// Recording writes crash-safe PCM; compression happens only once a meeting has finished.
public enum MeetingAudioFiles {
    public static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
    public static func hasAudio(_ url: URL) -> Bool { (duration(of: url) ?? 0) > 0 }

    /// Rewrites a PCM recording as AAC in an MPEG-4 container; the source is removed on success.
    public static func compress(_ source: URL, to destination: URL) throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 48_000 * Int(format.channelCount),
        ]
        try? FileManager.default.removeItem(at: destination)
        do {
            let output = try AVAudioFile(forWriting: destination, settings: settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw ScribeError.noAudioFormat }
            while input.framePosition < input.length {
                try input.read(into: buffer, frameCount: 8192)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        try FileManager.default.removeItem(at: source)
    }
}
