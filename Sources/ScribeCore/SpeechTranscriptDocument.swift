import Foundation
import NaturalLanguage

/// Only finalized stretches enter this document. Revisions replace one stretch and
/// invalidate its joined-text cache once; volatile updates just append the short tail.
struct SpeechTranscriptDocument: Sendable {
    struct Segment: Sendable {
        let id: Int
        let source: Int
        let start: Double
        let end: Double
        var text: String
        var confidence: Double
        var winner: Int?
    }
    private(set) var segments: [Segment] = []
    private(set) var text = ""
    private var pending: [SpeechToken] = []
    private var pendingWords = 0
    var boundary: Double { segments.last?.end ?? 0 }
    var pendingText: String { MixedLanguageTranscript.joinTokens(pending) }

    mutating func seed(_ lane: SpeechLane, source: Int, end: Double) {
        guard !lane.finalized.isEmpty else { return }
        segments = [.init(id: 0, source: source, start: lane.tokens.first?.start ?? 0, end: end,
                          text: lane.finalized.trimmingCharacters(in: .whitespacesAndNewlines),
                          confidence: lane.candidate.confidence, winner: source)]
        text = segments[0].text
    }

    mutating func append(_ tokens: [SpeechToken], source: Int, floor: Double = -.infinity) -> [Int] {
        var added: [Int] = []
        for token in tokens where token.midpoint >= floor {
            if let last = pending.last, token.start - last.end >= 0.35,
               last.end - (pending.first?.start ?? 0) >= 1.2 || pendingWords >= 3 {
                if let id = flush(source: source) { added.append(id) }
            }
            SpeechToken.append([token], to: &pending)
            pendingWords += token.words
            let punctuation = token.text.trimmingCharacters(in: .whitespacesAndNewlines).last
            let sentenceEnd = punctuation.map { ".!?。！？".contains($0) } ?? false
            if sentenceEnd {
                if let id = flush(source: source) { added.append(id) }
            }
        }
        if tokens.reduce(0, { $0 + $1.words }) >= 6, let id = flush(source: source) { added.append(id) }
        return added
    }

    mutating func flush(source: Int) -> Int? {
        guard let first = pending.first, let last = pending.last else { return nil }
        let id = segments.count
        let value = MixedLanguageTranscript.joinTokens(pending)
        segments.append(.init(id: id, source: source, start: first.start, end: last.end, text: value,
                              confidence: pending.reduce(0) { $0 + $1.confidence } / Double(pending.count), winner: nil))
        text = MixedLanguageTranscript.joinText(text, value)
        pending.removeAll(keepingCapacity: true)
        pendingWords = 0
        return id
    }

    mutating func discardPendingForReplay() { pending.removeAll(keepingCapacity: true); pendingWords = 0 }

    mutating func resolve(_ id: Int, candidate: LanguagePicker.Candidate, winner: Int) {
        segments[id].winner = winner
        segments[id].confidence = candidate.confidence
        guard segments[id].text != candidate.text else { return }
        segments[id].text = candidate.text
        text = segments.reduce(into: "") { $0 = MixedLanguageTranscript.joinText($0, $1.text) }
    }

    func candidate(locales: [Locale], active: Int) -> LanguagePicker.Candidate {
        var durations = Array(repeating: 0.0, count: locales.count)
        for segment in segments { durations[segment.winner ?? segment.source] += max(0, segment.end - segment.start) }
        let dominant = durations.indices.max(by: { durations[$0] < durations[$1] }) ?? active
        let confidence = segments.isEmpty ? 0 : segments.reduce(0) { $0 + $1.confidence } / Double(segments.count)
        return .init(locale: locales[dominant], text: MixedLanguageTranscript.joinText(text, pendingText), confidence: confidence)
    }
}

/// One bounded language check per finalized stretch, never per volatile result.
struct SpeechSentenceMonitor: Sendable {
    private(set) var baseline: Double
    init(baseline: Double) { self.baseline = baseline }

    mutating func suspicious(_ segment: SpeechTranscriptDocument.Segment, locale: Locale, among locales: [Locale]) -> Bool {
        guard MixedLanguageTranscript.wordCount(segment.text) >= 3 else { return false }
        if baseline > 0, baseline - segment.confidence >= 0.15, segment.confidence < baseline * 0.85 { return true }
        if let own = LanguagePicker.language(for: locale) {
            let languages = Set(locales.compactMap(LanguagePicker.language(for:)))
            if languages.count > 1 {
                let recognizer = NLLanguageRecognizer()
                recognizer.languageConstraints = Array(languages)
                recognizer.processString(segment.text)
                if let best = recognizer.dominantLanguage, best != own,
                   (recognizer.languageHypotheses(withMaximum: languages.count)[best] ?? 0) >= 0.65 { return true }
            }
        }
        if segment.confidence > 0 { baseline = baseline == 0 ? segment.confidence : baseline * 0.9 + segment.confidence * 0.1 }
        return false
    }
}
