import Foundation
import NaturalLanguage

/// Language is an utterance decision. Probe twice at most; only a release-time
/// suspicion check can request the inactive languages again.
struct SpeechLanguageLock: Sendable {
    private(set) var index: Int?
    private(set) var earlyConfidence = 0.0
    private var attemptedEarly = false
    private(set) var probeScores: [Double] = []
    private(set) var probeWords: [Int] = []

    mutating func consider(_ lanes: [SpeechLane], audioEnd: Double) -> Int? {
        guard index == nil, lanes.count > 1 else { return nil }
        let firstStart = lanes.flatMap { $0.tokens.prefix(1) + $0.volatileTokens.prefix(1) }.map(\.start).min() ?? 0
        let elapsed = audioEnd - firstStart
        let words = lanes.map { MixedLanguageTranscript.wordCount($0.finalized) }
        let evidenceWords = lanes.map { MixedLanguageTranscript.wordCount($0.text) }
        let ready = evidenceWords.allSatisfy { $0 >= 3 } && ((words.max() ?? 0) >= 6 || lanes.indices.contains {
            words[$0] >= 3 && (lanes[$0].tokens.last?.end ?? firstStart) - firstStart >= 3
        })
        let timedOut = elapsed >= 8
        guard (ready && !attemptedEarly) || timedOut else { return nil }
        let candidates = lanes.map { Self.probe($0, extended: timedOut) }
        guard candidates.contains(where: { MixedLanguageTranscript.wordCount($0.text) >= 3 }) else { return nil }
        attemptedEarly = true
        let languages = Set(lanes.compactMap { LanguagePicker.language(for: $0.locale) })
        let scores = candidates.map { $0.text.isEmpty ? 0 : LanguagePicker.score($0, among: languages) }
        guard let best = candidates.indices.filter({ MixedLanguageTranscript.wordCount(candidates[$0].text) >= 3 }).max(by: { scores[$0] < scores[$1] }) else { return nil }
        probeScores = scores
        probeWords = candidates.map { MixedLanguageTranscript.wordCount($0.text) }
        let runnerUp = scores.indices.filter { $0 != best }.map { scores[$0] }.max() ?? 0
        guard timedOut || scores[best] - runnerUp >= 0.15 else { return nil }
        index = best
        earlyConfidence = candidates[best].confidence
        return best
    }

    private static func probe(_ lane: SpeechLane, extended: Bool) -> LanguagePicker.Candidate {
        var tokens: [SpeechToken] = []
        var words = 0
        let evidence = SpeechToken.appending(lane.volatileTokens, to: lane.tokens)
        for token in evidence {
            tokens.append(token)
            words += token.words
            // A greeting such as "sì" must not outweigh the sentence that follows it.
            let end = token.text.trimmingCharacters(in: .whitespacesAndNewlines).last
            if words < 3, end.map({ ".!?。！？".contains($0) }) == true {
                tokens.removeAll(keepingCapacity: true)
                words = 0
                continue
            }
            if words >= 3, words >= (extended ? 20 : 6) || token.end - (tokens.first?.start ?? 0) >= (extended ? 8 : 3) { break }
        }
        if tokens.isEmpty {
            let value = lane.candidate
            return .init(locale: value.locale, text: value.text,
                         confidence: lane.confidenceCount > 0 ? value.confidence : 0.5)
        }
        return .init(locale: lane.locale, text: MixedLanguageTranscript.joinTokens(tokens),
                     confidence: tokens.reduce(0) { $0 + $1.confidence } / Double(tokens.count))
    }

}
