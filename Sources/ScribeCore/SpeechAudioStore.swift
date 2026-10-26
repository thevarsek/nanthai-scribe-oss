import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Capture, the bounded recent-audio cache and live-analyzer handoff share one actor,
/// so replay and newly arriving microphone packets cannot leave a gap or overlap.
actor SpeechAudioStore {
    private struct Packet: Sendable {
        let frame: AVAudioFramePosition
        let input: AnalyzerInput
        var end: AVAudioFramePosition { frame + AVAudioFramePosition(input.buffer.frameLength) }
    }
    struct Clip: Sendable {
        let url: URL
        let start: Double
        let fromRing: Bool
    }
    private let url: URL
    private let format: AVAudioFormat
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var packets: [Packet?] = []
    private var firstPacket = 0
    private let retainedSeconds: Double
    private var sink: AsyncStream<AnalyzerInput>.Continuation?
    private var ended = false
    private var errors: [String: String] = [:]
    private let engines: [any BatchTranscriber]
    private var batch: [String: BatchAudioBuffer] = [:]

    init(url: URL, format: AVAudioFormat, engines: [any BatchTranscriber] = [], retainedSeconds: Double = 30,
         sink: AsyncStream<AnalyzerInput>.Continuation?) throws {
        self.url = url
        self.format = format
        self.engines = engines
        self.retainedSeconds = retainedSeconds
        self.sink = sink
        file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        for engine in engines { batch[engine.id] = try BatchAudioBuffer(inputFormat: format, sampleRate: engine.sampleRate) }
    }

    func append(_ input: AnalyzerInput) {
        guard !ended else { return }
        do { try file?.write(from: input.buffer) }
        catch { errors["recovery"] = "Couldn't save the recording." }
        let packet = Packet(frame: frames, input: input)
        if retainedSeconds > 0 { packets.append(packet) }
        frames = packet.end
        let cutoff = frames - AVAudioFramePosition(retainedSeconds * format.sampleRate)
        while firstPacket < packets.count, let old = packets[firstPacket], old.end <= cutoff {
            packets[firstPacket] = nil
            firstPacket += 1
        }
        if firstPacket > 512, firstPacket > packets.count / 2 {
            packets.removeFirst(firstPacket)
            firstPacket = 0
        }
        for engine in engines where errors[engine.id] == nil {
            do { try batch[engine.id]?.append(input.buffer) }
            catch { errors[engine.id] = error.localizedDescription }
        }
        sink?.yield(stamped(packet))
    }

    func close() {
        ended = true
        file = nil
        sink?.finish()
        sink = nil
    }

    func discardCache() { close(); packets = []; firstPacket = 0; batch = [:] }

    var duration: Double { Double(frames) / format.sampleRate }
    var captureErrors: [String: String] { errors }
    var cachedSeconds: Double {
        guard let start = ringStart else { return 0 }
        return Double(frames - start) / format.sampleRate
    }

    /// A new analyzer hears the uncommitted tail before receiving future packets.
    func replaceSink(_ replacement: AsyncStream<AnalyzerInput>.Continuation, from seconds: Double) throws {
        let start = max(0, AVAudioFramePosition(seconds * format.sampleRate))
        let replay = try buffers(from: start, through: frames)
        sink?.finish()
        sink = replacement
        for packet in replay { replacement.yield(stamped(packet)) }
        if ended { replacement.finish(); sink = nil }
    }

    func clip(start: Double, end: Double, padding: Double = 0.2) throws -> Clip {
        let lower = max(0, AVAudioFramePosition((start - padding) * format.sampleRate))
        let upper = min(frames, AVAudioFramePosition(ceil((end + padding) * format.sampleRate)))
        let fromRing = ringStart.map { lower >= $0 } ?? false
        let destination = url.deletingLastPathComponent().appending(path: "span-\(UUID()).caf")
        do {
            let output = try AVAudioFile(forWriting: destination, settings: format.settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            for packet in try buffers(from: lower, through: upper) { try output.write(from: packet.input.buffer) }
            return Clip(url: destination, start: Double(lower) / format.sampleRate, fromRing: fromRing)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private var ringStart: AVAudioFramePosition? {
        firstPacket < packets.count ? packets[firstPacket]?.frame : nil
    }

    private func stamped(_ packet: Packet) -> AnalyzerInput {
        AnalyzerInput(buffer: packet.input.buffer,
                      bufferStartTime: CMTime(value: packet.frame, timescale: CMTimeScale(format.sampleRate)))
    }

    private func buffers(from lower: AVAudioFramePosition, through upper: AVAudioFramePosition) throws -> [Packet] {
        guard upper > lower else { return [] }
        if let start = ringStart, lower >= start {
            return try packets[firstPacket...].compactMap { entry in
                guard let packet = entry else { return nil }
                let start = max(lower, packet.frame), end = min(upper, packet.end)
                guard end > start else { return nil }
                return Packet(frame: start, input: AnalyzerInput(buffer: try Self.copy(packet.input.buffer,
                    offset: AVAudioFrameCount(start - packet.frame), count: AVAudioFrameCount(end - start))))
            }
        }
        let source = try AVAudioFile(forReading: url, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        source.framePosition = lower
        var position = lower
        var result: [Packet] = []
        while position < upper {
            let count = AVAudioFrameCount(min(4096, upper - position))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { throw ScribeError.noAudioFormat }
            try source.read(into: buffer, frameCount: count)
            guard buffer.frameLength > 0 else { throw ScribeError.noAudioFormat }
            result.append(Packet(frame: position, input: AnalyzerInput(buffer: buffer)))
            position += AVAudioFramePosition(buffer.frameLength)
        }
        return result
    }

    private static func copy(_ source: AVAudioPCMBuffer, offset: AVAudioFrameCount, count: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let output = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: count) else { throw ScribeError.noAudioFormat }
        output.frameLength = count
        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
        let bytes = Int(source.format.streamDescription.pointee.mBytesPerFrame)
        for index in input.indices {
            guard let from = input[index].mData, let to = target[index].mData else { throw ScribeError.noAudioFormat }
            memcpy(to, from.advanced(by: Int(offset) * bytes), Int(count) * bytes)
        }
        return output
    }

    func batchCandidates(locales: [Locale]) async -> [LanguagePicker.Candidate] {
        var candidates: [LanguagePicker.Candidate] = []
        for engine in engines where errors[engine.id] == nil {
            do {
                guard let buffer = batch[engine.id] else { continue }
                try buffer.finish()
                let result = try await engine.transcribe(samples: buffer.samples, sampleRate: engine.sampleRate)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let locale = BatchRouting.detectedLocale(for: text, among: BatchRouting.matching(locales, supportedBy: engine.languages)) {
                    candidates.append(.init(locale: locale, text: text, confidence: result.confidence ?? 0.5))
                }
            } catch { errors[engine.id] = error.localizedDescription }
        }
        batch = [:]
        return candidates
    }
}
