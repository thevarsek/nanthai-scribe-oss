import CoreMedia
import Foundation
import Speech
import Synchronization
import Testing
@_spi(Performance) @testable import ScribeCore

@Suite(.serialized) struct SpeechLanguageLockTests {
    let locales = [Locale(identifier: "en_US"), Locale(identifier: "it_IT")]
    let english = "Please bring the updated documents tomorrow morning."
    let italian = "Portiamo tutti i documenti alla riunione domani mattina."

    @Test func cleanEnglishAndItalianLockTheMatchingLane() {
        for (text, expected) in [(english, 0), (italian, 1)] {
            var lock = SpeechLanguageLock()
            let lanes = locales.map { lane($0, text, start: 0) }
            #expect(lock.consider(lanes, audioEnd: 3) == expected)
            #expect(lock.consider(lanes, audioEnd: 30) == nil)
            #expect(lock.index == expected)
        }
    }

    @Test func shortOpenersWaitForSubstantialEvidence() {
        for opener in ["Ok.", "Sì."] {
            var lock = SpeechLanguageLock()
            var lanes = locales.map { lane($0, opener, start: 0) }
            #expect(lock.consider(lanes, audioEnd: 0.5) == nil)
            #expect(lock.consider(lanes, audioEnd: 8) == nil)
            for index in lanes.indices { lanes[index].apply(timed(english, start: 1, end: 4), isFinal: true) }
            #expect(lock.consider(lanes, audioEnd: 4) == 0)
        }
    }

    @Test func aLaggingFinalLaneStillContributesItsVolatileLanguageEvidence() {
        var lanes = [lane(locales[0], italian, start: 0), SpeechLane(locale: locales[1])]
        lanes[1].apply(timed(italian, start: 0, end: 3, confidence: 0), isFinal: false)
        var lock = SpeechLanguageLock()
        #expect(lock.consider(lanes, audioEnd: 3) == 1)
    }

    @Test func ambiguousProbeWaitsUntilEightSeconds() {
        let lanes = [lane(locales[0], english, start: 0), lane(Locale(identifier: "en_GB"), english, start: 0)]
        var lock = SpeechLanguageLock()
        #expect(lock.consider(lanes, audioEnd: 3) == nil)
        #expect(lock.consider(lanes, audioEnd: 7.9) == nil)
        #expect(lock.consider(lanes, audioEnd: 8) != nil)
    }

    @Test @MainActor func oneItalianSentenceIsRevisedWithoutReplacingItsEnglishNeighbours() async {
        let log = ProcessorLog()
        let processor = makeProcessor(log)
        await lock(processor, text: english)
        await send(processor, "These are the wrong phonetic words here.", start: 4, confidence: 0.1)
        await waitFor { log.values.last?.text.contains(italian) == true }
        await send(processor, english, start: 8)
        let result = await processor.finish(batch: [])
        #expect(result?.text == english + " " + italian + " " + english)
        #expect(log.switches.isEmpty)
        #expect(log.values.last?.text == result?.text)
        #expect(log.values.last?.volatileText == "")
        await processor.cancel()
    }

    @Test @MainActor func permanentSwitchRelocksAfterTwoConsecutiveFlipsAndRejectsOldResults() async {
        let log = ProcessorLog()
        let processor = makeProcessor(log)
        await lock(processor, text: english)
        await send(processor, "These are the wrong phonetic words here.", start: 4, confidence: 0.1)
        await send(processor, "These are more wrong phonetic words here.", start: 8, confidence: 0.1)
        await waitFor { log.switches.count == 1 }
        #expect(log.switches.first?.index == 1)
        #expect(log.switches.first?.generation == 1)
        #expect(log.switches.first?.start == 10.8)
        await send(processor, "An obsolete result must never appear.", start: 12, index: 0, generation: 0)
        await send(processor, italian, start: 12, index: 1, generation: 1)
        let result = await processor.finish(batch: [])
        #expect(result?.text == english + " " + italian + " " + italian + " " + italian)
        #expect(!result!.text.contains("obsolete"))
        await processor.cancel()
    }

    @Test @MainActor func cleanThreeMinuteTakesNeverRequestARecheck() async {
        for (text, index) in [(english, 0), (italian, 1)] {
            let log = ProcessorLog()
            let samples = Mutex<[SpeechPerformanceSample]>([])
            let processor = makeProcessor(log, measure: { sample in samples.withLock { $0.append(sample) } })
            await lock(processor, text: text)
            for sentence in 1...60 { await send(processor, text, start: Double(sentence) * 3.2, index: index) }
            _ = await processor.finish(batch: [])
            #expect(samples.withLock { $0.filter { $0.phase == "spanRecheck" }.isEmpty })
            #expect(samples.withLock { $0.filter { $0.phase == "apply" }.allSatisfy { !$0.onMainThread } })
            #expect(log.switches.isEmpty)
            await processor.cancel()
        }
    }

    @Test @MainActor func languageDisagreementCanTriggerWithoutAConfidenceDrop() async {
        let log = ProcessorLog()
        let processor = makeProcessor(log)
        await lock(processor, text: english)
        await send(processor, italian, start: 4)
        let result = await processor.finish(batch: [])
        #expect(result?.text == english + " " + italian)
        await processor.cancel()
    }

    @Test @MainActor func burstsCoalesceButNewestFinalAndDeadlineSnapshotSurvive() async throws {
        let log = ProcessorLog()
        let processor = makeProcessor(log, locales: [locales[0]])
        for index in 0..<40 {
            await send(processor, "word\(index)", start: Double(index), isFinal: false)
        }
        await send(processor, english, start: 0)
        #expect(processor.latestSnapshot?.text == english)
        let result = await processor.finish(batch: [])
        #expect(log.values.count < 10)
        #expect(log.values.last?.text == english)
        #expect(result?.text == english)
        await processor.cancel()
        let count = log.values.count
        try await Task.sleep(for: .milliseconds(80))
        #expect(log.values.count == count)
    }

    @Test @MainActor func recognizerFailureCannotDropTheUnfinalizedTail() async {
        let log = ProcessorLog()
        let processor = makeProcessor(log)
        await lock(processor, text: english)
        await send(processor, english, start: 4, isFinal: false)
        let result = await processor.finish(batch: [])
        #expect(result?.text == english + " " + english)
        await processor.cancel()
    }

    @Test @MainActor func cancellationStopsTheInFlightSpan() async {
        let started = Mutex(false), cancelled = Mutex(false)
        let processor = SpeechTranscriptProcessor(locales: locales, displayIndex: 0, measure: nil,
            clip: { start, _ in .init(url: URL(filePath: "/tmp/unused-span-\(UUID()).caf"), start: start - 0.2, fromRing: true) },
            replay: { _, locale, _ in
                started.withLock { $0 = true }
                do { try await Task.sleep(for: .seconds(10)) }
                catch { cancelled.withLock { $0 = true }; throw error }
                return SpeechLane(locale: locale)
            }, switchLane: { _, _, _ in false }, update: { _ in })
        await lock(processor, text: english)
        await send(processor, english, start: 4, confidence: 0.1)
        await waitFor { started.withLock { $0 } }
        await processor.cancel()
        await waitFor { cancelled.withLock { $0 } }
        #expect(await processor.finish(batch: []) == nil)
    }

    @MainActor private func makeProcessor(_ log: ProcessorLog, locales chosen: [Locale]? = nil,
        measure: (@Sendable (SpeechPerformanceSample) -> Void)? = nil) -> SpeechTranscriptProcessor {
        let text = italian
        return SpeechTranscriptProcessor(locales: chosen ?? locales, displayIndex: 0, measure: measure,
            clip: { start, end in
                #expect(end - start <= 3.01)
                return .init(url: URL(filePath: "/tmp/unused-span-\(UUID()).caf"), start: max(0, start - 0.2), fromRing: true)
            }, replay: { _, locale, _ in
                var lane = SpeechLane(locale: locale)
                var result = AttributedString(text)
                result.audioTimeRange = CMTimeRange(start: CMTime(seconds: 0.2, preferredTimescale: 1000),
                                                    duration: CMTime(seconds: 2.6, preferredTimescale: 1000))
                result.transcriptionConfidence = 0.98
                lane.apply(result, isFinal: true)
                return lane
            }, switchLane: { index, generation, start in
                log.switches.append((index, generation, start))
                return true
            }, update: { log.values.append($0) })
    }

    private func lock(_ processor: SpeechTranscriptProcessor, text: String) async {
        for index in locales.indices { await send(processor, text, start: 0, index: index) }
    }

    private func send(_ processor: SpeechTranscriptProcessor, _ text: String, start: Double, confidence: Double = 0.95,
                      index: Int = 0, generation: Int = 0, isFinal: Bool = true) async {
        _ = await processor.apply(.init(text: timed(text, start: start, end: start + 3, confidence: confidence),
                                      isFinal: isFinal, start: start, end: start + 3, index: index, generation: generation))
    }

    @MainActor private func waitFor(_ predicate: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(predicate())
    }

    private func lane(_ locale: Locale, _ text: String, start: Double) -> SpeechLane {
        var lane = SpeechLane(locale: locale)
        lane.apply(timed(text, start: start, end: start + 3), isFinal: true)
        return lane
    }

    private func timed(_ text: String, start: Double, end: Double, confidence: Double = 0.95) -> AttributedString {
        var value = AttributedString(text)
        value.audioTimeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1000),
                                          end: CMTime(seconds: end, preferredTimescale: 1000))
        value.transcriptionConfidence = confidence
        return value
    }
}

@MainActor private final class ProcessorLog {
    var values: [SpeechTranscriptProcessor.Snapshot] = []
    var switches: [(index: Int, generation: Int, start: Double)] = []
}
