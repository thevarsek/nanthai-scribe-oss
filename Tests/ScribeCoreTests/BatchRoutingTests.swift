import AVFoundation
import Foundation
import Speech
import Testing
@testable import ScribeCore

struct BatchRoutingTests {
    let english = Locale(identifier: "en_GB")
    let dutch = Locale(identifier: "nl_NL")

    @Test func routesUnsupportedLanguageOnlyToBatch() {
        let apple = [Locale(identifier: "en_US"), Locale(identifier: "it_IT")]
        #expect(BatchRouting.batchOnly([english, dutch], appleLocales: apple) == [dutch])
        #expect(BatchRouting.matching([english, dutch], supportedBy: [dutch]) == [dutch])
    }

    @Test func appleResolverDoesNotRouteUnsupportedPackLanguages() async {
        let actualApple = await LiveTranscriber.supportedLocales
        let packOnly = BatchRouting.batchOnly(ParakeetTranscriber.supportedLanguages, appleLocales: actualApple)
        #expect(await LiveTranscriber.resolve(packOnly).isEmpty)
    }

    @Test func labelsDutchAmongSelectedLanguages() {
        let text = "Morgen gaan we met de trein naar Amsterdam. Vergeet niet om de kaartjes mee te nemen."
        #expect(BatchRouting.detectedLocale(for: text, among: [english, dutch]) == dutch)
    }

    @Test func preservesChosenRegionalLocale() {
        #expect(BatchRouting.detectedLocale(for: "Please send the final report before tomorrow morning.", among: [dutch, english]) == english)
    }

    @Test func cannotInventAnUnselectedLanguage() {
        #expect(BatchRouting.detectedLocale(for: "Bonjour, nous allons prendre le train demain matin.", among: [dutch]) == dutch)
        #expect(BatchRouting.detectedLocale(for: " ", among: [english, dutch]) == nil)
        #expect(BatchRouting.detectedLocale(for: "Hello", among: []) == nil)
    }

    @Test func catalogHas25Languages() {
        #expect(Set(ParakeetTranscriber.supportedLanguages.map(BatchRouting.languageCode)).count == 25)
    }

    @Test @MainActor func convertsIntegerStereoToFloatMonoAcrossChunks() throws {
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: false)!
        let converted = try BatchAudioBuffer(inputFormat: inputFormat, sampleRate: 16_000)
        for _ in 0..<12 {
            let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4000)!
            input.frameLength = 4000
            for channel in 0..<2 {
                input.int16ChannelData![channel].initialize(repeating: 8192, count: 4000)
            }
            try converted.append(input)
        }
        try converted.finish()
        #expect(abs(converted.samples.count - 16_000) < 100)
        #expect(converted.samples.allSatisfy { $0.isFinite })
        let middle = converted.samples.dropFirst(100).dropLast(100)
        #expect(abs(middle.reduce(0, +) / Float(middle.count) - 0.25) < 0.02)
    }

    @Test @MainActor func batchOnlySessionDrainsBeforeFinishing() async throws {
        // A deliberately unknown Apple locale makes this independent of installed OS assets.
        let locale = Locale(identifier: "zz_ZZ")
        let batch = RecordingBatch(languages: [locale])
        let live = LiveTranscriber()
        let (format, input) = try await live.start(locales: [locale], batchEngines: [batch])
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        audio.frameLength = 16_000
        audio.floatChannelData![0].initialize(repeating: 0.1, count: 16_000)
        input.yield(AnalyzerInput(buffer: audio))
        _ = await live.finish()
        #expect(await batch.sampleCount >= 15_900)
        #expect(live.batchErrors.isEmpty)
    }
}

private actor RecordingBatch: BatchTranscriber {
    nonisolated let id = "fixture"
    nonisolated let languages: [Locale]
    private(set) var sampleCount = 0
    init(languages: [Locale]) { self.languages = languages }
    func isAvailable() -> Bool { true }
    func transcribe(samples: [Float], sampleRate: Double) -> BatchTranscript {
        sampleCount = samples.count
        return BatchTranscript(text: "Test", confidence: 0.9)
    }
}
