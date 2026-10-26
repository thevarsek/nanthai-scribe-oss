import CoreMedia
import Foundation
import Speech
import Testing
@testable import ScribeCore

@Suite(.serialized) struct SpeechPunctuationBoundaryTests {
    private let locales = [Locale(identifier: "en_US"), Locale(identifier: "it_IT")]

    @Test(arguments: ["'", "’", ",", "."])
    func untimedPunctuationSharedByResultChunksAppearsOnce(_ mark: String) {
        let first = timed("Parliamo un po", start: 0, end: 2) + AttributedString(mark)
        let next = AttributedString(mark) + timed(" in italiano", start: 2.6, end: 4)
        var lane = SpeechLane(locale: locales[1])
        lane.apply(first, isFinal: true)
        lane.apply(next, isFinal: false)
        let expected = "Parliamo un po" + mark + " in italiano"
        #expect(lane.text == expected)
        #expect(MixedLanguageTranscript.joinTokens(SpeechToken.appending(lane.volatileTokens, to: lane.tokens)) == expected)
        lane.apply(next, isFinal: true)
        #expect(lane.text == expected)
        #expect(MixedLanguageTranscript.joinTokens(lane.tokens) == expected)

        var document = SpeechTranscriptDocument()
        _ = document.append(LiveTranscriber.timedTokens(first).tokens, source: 1)
        _ = document.append(LiveTranscriber.timedTokens(next).tokens, source: 1)
        #expect(document.candidate(locales: locales, active: 1).text == expected)
        _ = document.flush(source: 1)
        #expect(document.text == expected)
    }

    @Test(arguments: ["'", "’", ",", "."])
    func spanReplacementCanSharePunctuationWithEitherNeighbour(_ mark: String) {
        var document = SpeechTranscriptDocument()
        _ = document.append(LiveTranscriber.timedTokens(timed("Parliamo un po", start: 0, end: 2)).tokens, source: 0)
        _ = document.flush(source: 0)
        let next = AttributedString(mark) + timed(" in italiano", start: 2.1, end: 4)
        _ = document.append(LiveTranscriber.timedTokens(next).tokens, source: 0)
        _ = document.flush(source: 0)
        let replacement = "Parliamo un po" + mark
        document.resolve(0, candidate: .init(locale: locales[1], text: replacement, confidence: 0.99), winner: 1)
        #expect(document.text == replacement + " in italiano")
        document.resolve(1, candidate: .init(locale: locales[1], text: mark + " in italiano", confidence: 0.99), winner: 1)
        #expect(document.text == replacement + " in italiano")
    }

    @Test func boundaryJoiningPreservesRepeatedWordsAndInternalPunctuation() {
        #expect(MixedLanguageTranscript.joinText("Go", "go again...") == "Go go again...")
        #expect(MixedLanguageTranscript.joinText("He said", "use '' and then ‘ciao’.") == "He said use '' and then ‘ciao’.")
        #expect(MixedLanguageTranscript.joinText("Wait...", "... go.") == "Wait... go.")
        #expect(MixedLanguageTranscript.joinText("un po'", "’ in italiano") == "un po' in italiano")
        #expect(MixedLanguageTranscript.joinText("un po’", "' in italiano") == "un po’ in italiano")
        #expect(MixedLanguageTranscript.joinText("un po' ", " ' in italiano") == "un po' in italiano")
    }

    @Test(arguments: ["'", "’", ",", "."])
    func untimedPunctuationCanBeginTheNextResult(_ mark: String) {
        var lane = SpeechLane(locale: locales[1])
        lane.apply(timed("Parliamo un po", start: 0, end: 2), isFinal: true)
        lane.apply(AttributedString(mark) + timed(" in italiano", start: 2, end: 4), isFinal: true)
        let expected = "Parliamo un po" + mark + " in italiano"
        #expect(lane.text == expected)
        #expect(MixedLanguageTranscript.joinTokens(lane.tokens) == expected)
    }

    @Test @MainActor func punctuationOnlyResultCannotHideThePreviousBoundary() async {
        let english = "Please bring the updated documents tomorrow morning."
        for mark in ["'", "’", ",", "."] {
            let processor = SpeechTranscriptProcessor(locales: locales, displayIndex: 0, measure: nil,
                clip: { _, _ in throw CocoaError(.fileNoSuchFile) },
                switchLane: { _, _, _ in false }, update: { _ in })
            for index in locales.indices {
                _ = await processor.apply(.init(text: timed(english, start: 0, end: 3), isFinal: true,
                                                start: 0, end: 3, index: index, generation: 0))
            }
            var punctuation = AttributedString(mark)
            punctuation.transcriptionConfidence = 0.95
            let chunks: [(AttributedString, Double, Double)] = [
                (timed("We wait a bit", start: 4, end: 7) + punctuation, 4, 7),
                (punctuation, 7, 7),
                (punctuation + timed(" before continuing", start: 7.1, end: 9), 7.1, 9),
            ]
            for (text, start, end) in chunks {
                _ = await processor.apply(.init(text: text, isFinal: true, start: start, end: end, index: 0, generation: 0))
            }
            let result = await processor.finish(batch: [])
            #expect(result?.text == english + " We wait a bit" + mark + " before continuing")
            await processor.cancel()
        }
    }

    @Test @MainActor func paddedSpanReplayAndFinalHandoffDoNotDuplicateElision() async {
        for mark in ["'", "’", ",", "."] {
            let english = "Please bring the updated documents tomorrow morning."
            let replacement = "Parliamo ancora un po" + mark
            let processor = SpeechTranscriptProcessor(locales: locales, displayIndex: 0, measure: nil,
                clip: { start, end in
                    #expect(start == 4)
                    #expect(end == 7)
                    return .init(url: URL(filePath: "/tmp/unused-punctuation-\(UUID()).caf"), start: start - 0.2, fromRing: true)
                }, replay: { _, locale, _ in
                    var lane = SpeechLane(locale: locale)
                    // Neighbouring words in the ±0.2 s padding must stay outside the replacement.
                    lane.apply(timed("Before", start: 0, end: 0.1), isFinal: true)
                    lane.apply(timed("Parliamo ancora un po", start: 0.2, end: 3) + AttributedString(mark), isFinal: true)
                    lane.apply(timed("After", start: 3.25, end: 3.4), isFinal: true)
                    return lane
                }, switchLane: { _, _, _ in false }, update: { _ in })
            for index in locales.indices {
                _ = await processor.apply(.init(text: timed(english, start: 0, end: 3), isFinal: true,
                                                start: 0, end: 3, index: index, generation: 0))
            }
            _ = await processor.apply(.init(text: timed("These are the wrong phonetic words.", start: 4, end: 7, confidence: 0.1),
                                            isFinal: true, start: 4, end: 7, index: 0, generation: 0))
            let tail = AttributedString(mark) + timed(" Then we return to English.", start: 7.1, end: 10)
            _ = await processor.apply(.init(text: tail, isFinal: false, start: 7.1, end: 10, index: 0, generation: 0))
            let expected = english + " " + replacement + " Then we return to English."
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while processor.latestSnapshot?.text.contains(replacement) != true, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(processor.latestSnapshot?.text == expected)
            let result = await processor.finish(batch: [])
            #expect(result?.text == expected)
            #expect(processor.latestSnapshot?.text == result?.text)
            #expect(processor.latestSnapshot?.volatileText == "")
            await processor.cancel()
        }
    }
}

private func timed(_ text: String, start: Double, end: Double, confidence: Double = 0.95) -> AttributedString {
    var value = AttributedString(text)
    value.audioTimeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1000),
                                      end: CMTime(seconds: end, preferredTimescale: 1000))
    value.transcriptionConfidence = confidence
    return value
}
