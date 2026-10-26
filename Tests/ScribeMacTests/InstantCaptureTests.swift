import AVFoundation
import Foundation
import Speech
@testable import ScribeCore
import Testing
@testable import ScribeMac

/// Audio spoken while the speech analyzer is still starting must survive, in order.
/// `MicrophoneRoute` stands in for the hardware tap: tests feed it buffers the way the engine would.
@Suite(.serialized) struct InstantCaptureTests {
    private static func ramp(_ range: Range<Int>, sampleRate: Double = 48_000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count))!
        buffer.frameLength = AVAudioFrameCount(range.count)
        for (i, v) in range.enumerated() { buffer.floatChannelData![0][i] = Float(v) / 1_000_000 }
        return buffer
    }

    @Test func preRollAndLiveAudioArriveOnceAndInOrder() async {
        let route = MicrophoneRoute(onLevel: { _ in })
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let (stream, sink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        for chunk in 0..<10 { route.receive(Self.ramp(chunk * 1_000..<(chunk + 1) * 1_000)) }
        #expect(route.bufferedSeconds > 0.2)
        route.attach(target: target, sink: sink, formatChanged: nil)
        #expect(route.bufferedSeconds == 0)
        for chunk in 10..<20 { route.receive(Self.ramp(chunk * 1_000..<(chunk + 1) * 1_000)) }
        sink.finish()
        var samples: [Float] = []
        for await packet in stream {
            let b = packet.buffer
            samples += UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength))
        }
        #expect(samples.count == 20_000)
        #expect(samples == (0..<20_000).map { Float($0) / 1_000_000 })
    }

    @Test func preRollIsBounded() {
        let route = MicrophoneRoute(onLevel: { _ in })
        for _ in 0..<(Int(Microphone.prerollLimit) + 20) { route.receive(Self.ramp(0..<48_000)) }
        #expect(route.bufferedSeconds <= Microphone.prerollLimit)
    }

    /// The first words are spoken before the analyzer exists; they must still be transcribed.
    @Test func firstWordsSurviveASlowTranscriberStart() async throws {
        guard await MeetingFixtures.installed("en_US") else { return }
        let url = try MeetingFixtures.clip("Samantha", "Hello there. Remember to buy oranges and milk on the way home.")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        var chunks: [AVAudioPCMBuffer] = []
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
            try file.read(into: buffer, frameCount: 4096)
            chunks.append(buffer)
        }
        let route = MicrophoneRoute(onLevel: { _ in })
        let split = chunks.count / 2
        let transcriber = await LiveTranscriber()
        let keyDown = ContinuousClock.now
        for chunk in chunks[..<split] { route.receive(chunk) }
        try await Task.sleep(for: .seconds(2))   // a cold analyzer start, while the user keeps talking
        let (target, sink) = try await transcriber.start(locales: [Locale(identifier: "en_US")])
        let ready = CaptureTiming.milliseconds(from: keyDown, to: .now)
        route.attach(target: target, sink: sink, formatChanged: nil)
        for chunk in chunks[split...] { route.receive(chunk) }
        let (text, _) = await transcriber.finish()
        print("INSTANT-CAPTURE transcriber ready after \(ready) ms; transcript: \(text)")
        let lowered = text.lowercased()
        #expect(lowered.contains("hello"))
        #expect(lowered.contains("oranges"))
        await transcriber.discardRetainedTake()
    }

    /// Reports (not asserts) how much `prewarm` saves on the transcriber start path.
    @Test func prewarmTimings() async throws {
        let installed = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
        guard installed.isSuperset(of: ["it_IT", "en_GB"]) else { return }
        let locales = ["it_IT", "en_GB"].map(Locale.init(identifier:))
        func timedStart() async throws -> Int {
            let transcriber = await LiveTranscriber()
            let start = ContinuousClock.now
            _ = try await transcriber.start(locales: locales)
            let ms = CaptureTiming.milliseconds(from: start, to: .now)
            await transcriber.cancel()
            await transcriber.discardRetainedTake()
            return ms
        }
        let first = try await timedStart()
        let second = try await timedStart()
        let warmStart = ContinuousClock.now
        await LiveTranscriber.prewarm(locales: locales)
        let warm = CaptureTiming.milliseconds(from: warmStart, to: .now)
        let third = try await timedStart()
        print("INSTANT-CAPTURE start: first \(first) ms, second \(second) ms, prewarm \(warm) ms, start after prewarm \(third) ms")
    }
}
