import CoreMedia
import Foundation
import Speech
import Testing
@testable import ScribeCore

// NL is synchronous: do not occupy every cooperative-executor worker while the
// package's async deadline tests are sharing this process.
@Suite(.serialized) struct MixedLanguageTranscriptTests {
    let it = Locale(identifier: "it_IT")
    let en = Locale(identifier: "en_US")

    func tokens(_ text: String, start: Double, confidence: Double = 0.95) -> [SpeechToken] {
        text.split(separator: " ").enumerated().map { index, word in
            .init(text: String(word) + " ", start: start + Double(index) * 0.3,
                  end: start + Double(index) * 0.3 + 0.25, confidence: confidence)
        }
    }

    func lane(_ locale: Locale, _ tokens: [SpeechToken]) -> SpeechLane {
        var lane = SpeechLane(locale: locale)
        lane.tokens = tokens
        lane.finalized = MixedLanguageTranscript.joinTokens(tokens)
        lane.confidenceSum = tokens.map(\.confidence).reduce(0, +)
        lane.confidenceCount = tokens.count
        return lane
    }

    func volatileLane(_ locale: Locale, _ tokens: [SpeechToken]) -> SpeechLane {
        var result = SpeechLane(locale: locale)
        result.volatile = MixedLanguageTranscript.joinTokens(tokens)
        result.volatileTokens = tokens
        return result
    }

    @Test func italianThenEnglishAndDominantDuration() {
        let italian = "Ciao Marco, ci vediamo giovedì alle dieci."
        let english = "Let me know if that still works for you."
        let lanes = [lane(it, tokens(italian, start: 0) + tokens(english, start: 3)),
                     lane(en, tokens("Chow Marco che vediamo joe vedi alle dieci.", start: 0, confidence: 0.5)
                          + tokens(english, start: 3))]
        var selector = MixedLanguageTranscript()
        let result = selector.select(lanes, live: false)
        #expect(result?.text == italian + " " + english)
        #expect(result?.locale == en)
        var reverse = MixedLanguageTranscript()
        let reverseLanes = [lane(it, tokens(english, start: 0) + tokens(italian, start: 4)),
                            lane(en, tokens(english, start: 0) + tokens("Chow Marco che vediamo joe vedi alle dieci.", start: 4, confidence: 0.5))]
        #expect(reverse.select(reverseLanes, live: false)?.text == english + " " + italian)
    }

    @Test func shortInterjectionInheritsNeighbour() {
        let first = "Possiamo andare al cinema questa sera."
        let last = "Ci vediamo davanti alla stazione domani."
        let italian = tokens(first, start: 0) + tokens("Ok.", start: 4, confidence: 0.5) + tokens(last, start: 6)
        let english = tokens(first, start: 0) + tokens("Okay.", start: 4, confidence: 0.99) + tokens(last, start: 6)
        var selector = MixedLanguageTranscript()
        #expect(selector.select([lane(it, italian), lane(en, english)], live: false)?.text == first + " Ok. " + last)
    }

    @Test func singleLaneIsByteIdenticalIncludingWhitespaceAndVolatileTail() {
        var original = SpeechLane(locale: it)
        original.apply(AttributedString("  Ciao Marco,\n"), isFinal: true)
        original.apply(AttributedString(" this is replaced"), isFinal: false)
        original.apply(AttributedString(" ci vediamo giovedì.  "), isFinal: false)
        var selector = MixedLanguageTranscript()
        #expect(selector.select([original], live: false)?.text == original.candidate.text)
        #expect(original.text == "  Ciao Marco,\n ci vediamo giovedì.  ")
        #expect(LiveTranscriber.join("hello", ", world") == "hello , world")
        original.apply(AttributedString(" ci vediamo venerdì.  "), isFinal: true)
        #expect(original.text == "  Ciao Marco,\n ci vediamo venerdì.  ")
        #expect(original.candidate.text == "Ciao Marco,\n ci vediamo venerdì.")
    }

    @Test func missingTimingUsesWholeUtterancePicker() {
        var italian = lane(it, tokens("Ci vediamo domani mattina alla stazione.", start: 0))
        italian.hasTiming = false
        let english = lane(en, tokens("See you tomorrow morning at the station.", start: 0, confidence: 0.5))
        let lanes = [italian, english]
        var selector = MixedLanguageTranscript()
        let expected = LanguagePicker.best(of: lanes.map(\.candidate))
        #expect(selector.select(lanes, live: false)?.text == expected?.text)
        #expect(selector.select(lanes, live: true)?.locale == expected?.locale)
    }

    @Test func liveTailRequiresTwoClearLeadsAndResetsOnInterruptedLead() {
        let english = "Let me know if that still works for you."
        let englishLanes = [volatileLane(it, tokens(english, start: 0)), volatileLane(en, tokens(english, start: 0))]
        let italian = "Ci vediamo domani mattina alla stazione."
        let italianLanes = [volatileLane(it, tokens(italian, start: 0)), volatileLane(en, tokens(italian, start: 0))]
        var selector = MixedLanguageTranscript(displayIndex: 0)
        #expect(selector.select(englishLanes, live: true)?.locale == it)
        #expect(selector.select(italianLanes, live: true)?.locale == it)
        #expect(selector.select(englishLanes, live: true)?.locale == it)
        #expect(selector.select(englishLanes, live: true)?.locale == en)
        #expect(selector.select(italianLanes, live: true)?.locale == en)
        #expect(selector.select(italianLanes, live: false)?.locale == it)
    }

    @Test func finalizedWindowNeedsLargeNewMarginToChange() {
        let gb = Locale(identifier: "en_GB")
        func lanes(_ confidence: Double) -> [SpeechLane] {
            [lane(en, tokens("We can go.", start: 0, confidence: 0.6)
                  + tokens("Please call me tomorrow.", start: 2)),
             lane(gb, tokens("We might go.", start: 0, confidence: confidence)
                  + tokens("Please call me tomorrow.", start: 2))]
        }
        var selector = MixedLanguageTranscript()
        #expect(selector.select(lanes(0.55), live: true)?.text.hasPrefix("We can go.") == true)
        #expect(selector.select(lanes(0.7), live: true)?.text.hasPrefix("We can go.") == true)
        #expect(selector.select(lanes(0.95), live: true)?.text.hasPrefix("We might go.") == true)
    }

    @Test func volatileTokensAreReplacedRatherThanAccumulated() {
        var lane = SpeechLane(locale: en)
        func timed(_ text: String) -> AttributedString {
            var value = AttributedString(text)
            value.audioTimeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1000))
            value.transcriptionConfidence = 0.9
            return value
        }
        lane.apply(timed("We can"), isFinal: false)
        lane.apply(timed("We can go."), isFinal: false)
        #expect(lane.tokens.isEmpty)
        #expect(lane.volatileTokens.count == 1)
        lane.apply(timed("We could go."), isFinal: true)
        #expect(lane.volatileTokens.isEmpty)
        #expect(lane.tokens.count == 1)
        #expect(lane.text == "We could go.")
    }

    @Test func batchWinnerStaysWholeAndSingleLanePassesThrough() {
        let lanes = [lane(it, tokens("Ci vediamo domani alla stazione.", start: 0, confidence: 0.3)),
                     lane(en, tokens("See you tomorrow at the station.", start: 0, confidence: 0.3))]
        let batch = LanguagePicker.Candidate(locale: en, text: "This is the complete batch transcript.", confidence: 1)
        #expect(MixedLanguageTranscript.finalSelection(lanes: lanes, batch: [batch])?.text == batch.text)
        #expect(MixedLanguageTranscript.finalSelection(lanes: [lanes[0]], batch: [])?.text == lanes[0].candidate.text)
        #expect(MixedLanguageTranscript.finalSelection(lanes: [], batch: [batch])?.text == batch.text)
    }

    @Test func coarseVolatileRangeCannotReplaceAnEarlierCorrectPrefix() {
        let italian = "Ciao Marco, ci vediamo giovedì alle dieci."
        var selector = MixedLanguageTranscript()
        let coarse = SpeechToken(text: italian, start: 0, end: 5, confidence: 0.5)
        let initial = [volatileLane(it, [coarse]), volatileLane(en, [coarse])]
        #expect(selector.select(initial, live: true)?.text == italian)
        var lagging = initial
        lagging[1] = lane(en, tokens("Chow Marco come see the movie.", start: 0, confidence: 0.4))
        lagging[1].volatileTokens = [SpeechToken(text: " Let me know.", start: 3, end: 5, confidence: 0.5)]
        #expect(selector.select(lagging, live: true)?.text == italian)
    }

    @Test func coarseVolatileTailKeepsGrowingAcrossFinalizedSentenceCuts() {
        let opening = "Ciao Marco, ci vediamo giovedì alle dieci."
        let continuation = "Portiamo tutti i documenti del progetto per controllare insieme ogni dettaglio della proposta prima di preparare il calendario definitivo e inviare le nuove informazioni a tutte le persone che partecipano alla riunione della prossima settimana"
        var selector = MixedLanguageTranscript()
        var active = volatileLane(it, [.init(text: opening, start: 0, end: 5, confidence: 0.5)])
        let lagging = lane(en, tokens("Chow Marco. Come see the movie.", start: 0, confidence: 0.4))
        var previousCount = selector.select([active, lagging], live: true)?.text.count ?? 0
        for (index, word) in continuation.split(separator: " ").enumerated() {
            active.volatile += " " + word
            active.volatileTokens = [.init(text: active.volatile, start: 0,
                end: 5 + Double(index + 1) * 0.2, confidence: 0.5)]
            let published = selector.select([active, lagging], live: true)?.text ?? ""
            #expect(published.count > previousCount)
            #expect(published.hasPrefix(opening))
            #expect(selector.volatileText == published)
            previousCount = published.count
        }
    }

    @Test func liveMetadataDimsOnlyTheSelectedVolatileSuffix() {
        let first = "We can go."
        let tail = "See you soon."
        var left = lane(en, tokens(first, start: 0))
        var right = lane(Locale(identifier: "en_GB"), tokens(first, start: 0))
        left.volatile = tail
        right.volatile = tail
        left.volatileTokens = [.init(text: tail, start: 1, end: 2, confidence: 0.5)]
        right.volatileTokens = left.volatileTokens
        var selector = MixedLanguageTranscript()
        #expect(selector.select([left, right], live: true)?.text == first + " " + tail)
        #expect(selector.volatileText == tail)
        left.tokens = SpeechToken.appending(left.volatileTokens, to: left.tokens)
        right.tokens = left.tokens
        left.volatileTokens = []
        right.volatileTokens = []
        _ = selector.select([left, right], live: true)
        #expect(selector.volatileText.isEmpty)
    }

    @Test func zeroConfidenceVolatileUsesLivePriorAndFinalKeepsActualValue() {
        var value = AttributedString("Let me know.")
        value.audioTimeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1000))
        value.transcriptionConfidence = 0
        var lane = SpeechLane(locale: en)
        lane.apply(value, isFinal: false)
        #expect(lane.volatileTokens.first?.confidence == 0.5)
        lane.apply(value, isFinal: true)
        #expect(lane.tokens.first?.confidence == 0)
    }

    @Test func switchingLanesDoesNotDuplicateAWordStraddlingTheCut() {
        let first = "We will see you."
        let second = "Ci vediamo domani mattina alla stazione."
        let italian = tokens("We will see", start: 0)
            + [SpeechToken(text: " you.", start: 0.9, end: 1.4, confidence: 0.9)]
            + tokens(second, start: 1.4)
        let english = tokens(first, start: 0)
            + tokens("Chee vediamo do many matina alla station for you.", start: 1.15, confidence: 0.3)
        let result = MixedLanguageTranscript.finalSelection(lanes: [lane(it, italian), lane(en, english)], batch: [])
        #expect(result?.text == first + " " + second)
    }

    @Test func removesOnlyRepeatedBoundaryWordsWithOverlappingAudio() {
        let head = [SpeechToken(text: " you.", start: 1.74, end: 2.04, confidence: 0.9)]
        let tail = [SpeechToken(text: " you.", start: 1.8, end: 2.28, confidence: 0.8),
                    SpeechToken(text: " Ciao", start: 2.28, end: 2.7, confidence: 0.9)]
        #expect(MixedLanguageTranscript.removingBoundaryOverlap(tail, after: head).count == 1)
        let repeated = [SpeechToken(text: " you.", start: 2.1, end: 2.4, confidence: 0.9)]
        #expect(MixedLanguageTranscript.removingBoundaryOverlap(repeated, after: head).count == 1)
        #expect(MixedLanguageTranscript.removingBoundaryOverlap(tail, after: []).count == 2)
    }

    @Test func separateResultChunksKeepLegacyWordSpacing() {
        func timed(_ text: String, _ start: Double) -> AttributedString {
            var value = AttributedString(text)
            value.audioTimeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1000),
                                              duration: CMTime(seconds: 1, preferredTimescale: 1000))
            value.transcriptionConfidence = 0.9
            return value
        }
        var lane = SpeechLane(locale: en)
        lane.apply(timed("Hello", 0), isFinal: true)
        lane.apply(timed("world.", 1), isFinal: true)
        lane.apply(timed("See you.", 2), isFinal: false)
        #expect(lane.text == "Hello world. See you.")
        #expect(MixedLanguageTranscript.joinTokens(lane.tokens) == "Hello world.")
        let evidence = SpeechToken.appending(lane.volatileTokens, to: lane.tokens)
        #expect(MixedLanguageTranscript.joinTokens(evidence) == lane.text)
    }

    @Test func punctuationAndUnspacedScripts() {
        #expect(MixedLanguageTranscript.joinText("Ciao Marco", ", see you Thursday.") == "Ciao Marco, see you Thursday.")
        #expect(MixedLanguageTranscript.joinText("你好", "世界。") == "你好世界。")
    }

    @Test func extractsTimingAndDetectsMissingWordAttributes() {
        var word = AttributedString("Ciao")
        word.audioTimeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 0.4, preferredTimescale: 1000))
        word.transcriptionConfidence = 0.9
        word += AttributedString(", ")
        let result = LiveTranscriber.timedTokens(word)
        #expect(result.complete)
        #expect(result.tokens.count == 1)
        #expect(result.tokens.first?.text == "Ciao, ")
        #expect(result.tokens.first?.end == 0.4)
        word += AttributedString("Marco")
        #expect(!LiveTranscriber.timedTokens(word).complete)
    }
}
