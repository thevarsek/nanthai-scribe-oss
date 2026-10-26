import AVFoundation
import CoreMedia
import Foundation
import Speech
import Testing
@testable import ScribeCore

@Suite(.serialized) struct SpeechAudioStoreTests {
    @Test func ringIsBoundedAndOlderSpansUseTheOpenRetainedFile() async throws {
        let root = URL(filePath: "/tmp/scribe-ring-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let store = try SpeechAudioStore(url: root.appending(path: "take.caf"), format: format, retainedSeconds: 1, sink: nil)
        for index in 0..<30 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
            buffer.frameLength = 1600
            buffer.floatChannelData![0].initialize(repeating: Float(index), count: 1600)
            await store.append(AnalyzerInput(buffer: buffer))
        }
        #expect(await store.cachedSeconds <= 1.11)
        let recent = try await store.clip(start: 2.2, end: 2.6, padding: 0)
        let older = try await store.clip(start: 0.2, end: 0.6, padding: 0)
        #expect(recent.fromRing)
        #expect(!older.fromRing)
        for (clip, value) in [(recent, Float(22)), (older, Float(2))] {
            let file = try AVAudioFile(forReading: clip.url)
            #expect(file.length == 6400)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1))
            try file.read(into: buffer, frameCount: 1)
            #expect(buffer.floatChannelData![0][0] == value)
        }
        await store.close()
    }

    @Test func packetTimestampsRetainExactSamplePrecisionAfterConverterPriming() async throws {
        let root = URL(filePath: "/tmp/scribe-sample-time-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false))
        let store = try SpeechAudioStore(url: root.appending(path: "take.caf"), format: format, sink: nil)
        let counts = [719] + Array(repeating: 720, count: 40)
        for count in counts {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
            buffer.frameLength = AVAudioFrameCount(count)
            buffer.floatChannelData![0].initialize(repeating: 0, count: count)
            await store.append(AnalyzerInput(buffer: buffer))
        }
        let (stream, sink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await store.replaceSink(sink, from: 0)
        await store.close()
        var frame: Int64 = 0
        for await packet in stream {
            #expect(packet.bufferStartTime == CMTime(value: frame, timescale: 24000))
            frame += Int64(packet.buffer.frameLength)
        }
        #expect(frame == Int64(counts.reduce(0, +)))
    }

    @Test func handoffReplaysTheTailThenForwardsNewPacketsWithoutAGap() async throws {
        let root = URL(filePath: "/tmp/scribe-handoff-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let store = try SpeechAudioStore(url: root.appending(path: "take.caf"), format: format, sink: nil)
        func packet() throws -> AnalyzerInput {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
            buffer.frameLength = 1600
            buffer.floatChannelData![0].initialize(repeating: 0, count: 1600)
            return AnalyzerInput(buffer: buffer)
        }
        for _ in 0..<3 { await store.append(try packet()) }
        let (stream, sink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await store.replaceSink(sink, from: 0.15)
        await store.append(try packet())
        await store.close()
        var times: [Double] = [], frames = 0
        for await packet in stream { times.append(packet.bufferStartTime!.seconds); frames += Int(packet.buffer.frameLength) }
        #expect(times == [0.15, 0.2, 0.3])
        #expect(frames == 4000)
    }
}
