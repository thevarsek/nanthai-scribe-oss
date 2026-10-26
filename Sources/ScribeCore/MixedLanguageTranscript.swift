import Foundation
import NaturalLanguage

/// Timed evidence from parallel recognizers. Text retains the recognizer's whitespace.
struct SpeechToken: Sendable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
    let words: Int

    init(text: String, start: Double, end: Double, confidence: Double, words: Int? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
        self.words = words ?? MixedLanguageTranscript.wordCount(text)
    }

    var midpoint: Double { (start + end) / 2 }

    static func appending(_ tail: [SpeechToken], to head: [SpeechToken]) -> [SpeechToken] {
        var result = head
        append(tail, to: &result)
        return result
    }

    /// Appending in place keeps the finalized buffer uniquely owned between results.
    static func append(_ tail: [SpeechToken], to head: inout [SpeechToken]) {
        var tail = tail[...]
        if let last = head.last {
            while let first = tail.first {
                let joined = LiveTranscriber.join(last.text, first.text)
                let text = String(joined.dropFirst(last.text.count))
                // A consumed punctuation-only chunk must not hide the preceding edge
                // from the next result (or from the next token in this result).
                if text.isEmpty { tail = tail.dropFirst(); continue }
                tail[tail.startIndex] = .init(text: text, start: first.start,
                                            end: first.end, confidence: first.confidence, words: first.words)
                break
            }
        }
        head.append(contentsOf: tail)
    }
}

struct SpeechLane: Sendable {
    let locale: Locale
    var finalized = ""
    var volatile = ""
    var confidenceSum = 0.0
    var confidenceCount = 0
    var tokens: [SpeechToken] = []
    var volatileTokens: [SpeechToken] = []
    var hasTiming = true
    var volatileHasTiming = true

    init(locale: Locale) { self.locale = locale }

    mutating func apply(_ text: AttributedString, isFinal: Bool, countWords: Bool = true) {
        let segment = String(text.characters)
        let timed = LiveTranscriber.timedTokens(text, countWords: countWords)
        if isFinal {
            LiveTranscriber.append(segment, to: &finalized)
            volatile = ""
            SpeechToken.append(timed.tokens, to: &tokens)
            hasTiming = hasTiming && timed.complete
            volatileTokens = []
            volatileHasTiming = true
            var sum = 0.0, count = 0
            for run in text.runs {
                if let confidence = run.transcriptionConfidence { sum += confidence; count += 1 }
            }
            confidenceSum += sum
            confidenceCount += count
        } else {
            volatile = segment
            // Apple reports zero confidence for coarse volatile ranges. Keep the live
            // neutral prior; finalized scores use the recognizer's actual confidence.
            volatileTokens = timed.tokens.map {
                SpeechToken(text: $0.text, start: $0.start, end: $0.end,
                            confidence: $0.confidence > 0 ? $0.confidence : 0.5, words: $0.words)
            }
            volatileHasTiming = timed.complete
        }
    }

    var text: String { LiveTranscriber.join(finalized, volatile) }
    var candidate: LanguagePicker.Candidate {
        .init(locale: locale, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
              confidence: confidenceCount > 0 ? confidenceSum / Double(confidenceCount) : 0)
    }
}

/// Selects coherent stretches of audio, rather than splicing independently guessed words.
/// Used only at release when language probing stayed ambiguous or a take needs recovery.
struct MixedLanguageTranscript {
    struct Window {
        let start: Double
        let end: Double
        let candidates: [LanguagePicker.Candidate]
        let tokens: [[SpeechToken]]
        let wordCount: Int
        var winner: Int
    }

    static func finalSelection(lanes: [SpeechLane], batch: [LanguagePicker.Candidate]) -> LanguagePicker.Candidate? {
        let candidates = lanes.map(\.candidate) + batch
        guard let best = LanguagePicker.bestIndex(of: candidates) else { return nil }
        // Batch engines have no word timeline and remain whole-utterance candidates.
        guard best < lanes.count, lanes.count > 1 else { return candidates[best] }
        var selector = MixedLanguageTranscript()
        return selector.select(lanes)
    }

    mutating func select(_ lanes: [SpeechLane]) -> LanguagePicker.Candidate? {
        guard lanes.count > 1 else {
            return lanes.first?.candidate
        }
        guard lanes.allSatisfy({ $0.hasTiming && $0.volatileHasTiming }) else {
            return wholeLaneSelection(lanes)
        }
        let evidence = lanes.map { SpeechToken.appending($0.volatileTokens, to: $0.tokens) }
        guard let reference = evidence.max(by: { $0.count < $1.count }), !reference.isEmpty else {
            return wholeLaneSelection(lanes)
        }
        let languages = Set(lanes.compactMap { LanguagePicker.language(for: $0.locale) })
        let start = evidence.flatMap { $0 }.map(\.start).min() ?? 0
        let end = evidence.flatMap { $0 }.map(\.end).max() ?? 0
        var cuts = [start]
        var words = 0
        for index in reference.indices.dropLast() {
            let token = reference[index], next = reference[index + 1]
            words += token.words
            let punctuation = token.text.trimmingCharacters(in: .whitespacesAndNewlines).last
            let sentenceEnd = punctuation.map { ".!?。！？".contains($0) } ?? false
            if (next.start - token.end >= 0.35 || sentenceEnd),
               token.end - cuts.last! >= 1.2 || words >= 3 {
                cuts.append((token.end + next.start) / 2)
                words = 0
            }
        }
        cuts.append(end)
        var windows: [Window] = []
        var cursors = Array(repeating: 0, count: lanes.count)
        let ordered = evidence.allSatisfy { tokens in
            zip(tokens, tokens.dropFirst()).allSatisfy { $0.midpoint <= $1.midpoint }
        } && zip(cuts, cuts.dropFirst()).allSatisfy { $0 <= $1 }
        for index in 0..<(cuts.count - 1) {
            let lower = cuts[index], upper = cuts[index + 1]
            let windowTokens = evidence.indices.map { lane -> [SpeechToken] in
                let tokens = evidence[lane]
                guard ordered else {
                    return tokens.filter { $0.midpoint >= lower && ($0.midpoint < upper || index == cuts.count - 2) }
                }
                while cursors[lane] < tokens.count, tokens[cursors[lane]].midpoint < lower { cursors[lane] += 1 }
                let first = cursors[lane]
                while cursors[lane] < tokens.count,
                      tokens[cursors[lane]].midpoint < upper || index == cuts.count - 2 { cursors[lane] += 1 }
                return Array(tokens[first..<cursors[lane]])
            }
            let candidates = lanes.indices.map { lane in
                let tokens = windowTokens[lane]
                return LanguagePicker.Candidate(locale: lanes[lane].locale,
                    text: Self.joinTokens(tokens),
                    confidence: tokens.isEmpty ? 0 : tokens.map(\.confidence).reduce(0, +) / Double(tokens.count))
            }
            let scores = candidates.map { $0.text.isEmpty ? 0 : LanguagePicker.score($0, among: languages) }
            let winner = candidates.indices.filter { !candidates[$0].text.isEmpty }
                .max(by: { scores[$0] < scores[$1] }) ?? 0
            windows.append(.init(start: lower, end: upper, candidates: candidates, tokens: windowTokens,
                                 wordCount: candidates.map { Self.wordCount($0.text) }.max() ?? 0, winner: winner))
        }
        // DESIGN: Below three words, neighbour bias is inheritance when that lane has
        // text here: NL can confidently mislabel "ok" or "sì". Isolated word switches
        // are best-effort. Keep raw substantial winners for smoothing both neighbours.
        let substantial = windows.indices.filter { windows[$0].wordCount >= 3 }
        for index in windows.indices where windows[index].wordCount < 3 {
            if let neighbour = substantial.min(by: { abs($0 - index) < abs($1 - index) }) {
                let winner = windows[neighbour].winner
                if !windows[index].candidates[winner].text.isEmpty { windows[index].winner = winner }
            }
        }
        var text = ""
        var emitted: [SpeechToken] = []
        var lastWinner: Int?
        var durations = Array(repeating: 0.0, count: lanes.count)
        // Joining consecutive windows with one winner also merges their output without
        // a second text-language pass that could erase a real switch.
        for window in windows {
            var tokens = window.tokens[window.winner]
            if let lastWinner, lastWinner != window.winner {
                tokens = Self.removingBoundaryOverlap(tokens, after: emitted)
            }
            Self.appendText(Self.joinTokens(tokens), to: &text)
            emitted += tokens
            lastWinner = window.winner
            durations[window.winner] += window.end - window.start
        }
        let dominant = durations.indices.max(by: { durations[$0] < durations[$1] }) ?? 0
        let selection = LanguagePicker.Candidate(locale: lanes[dominant].locale, text: text, confidence: 0)
        return selection
    }

    private func wholeLaneSelection(_ lanes: [SpeechLane]) -> LanguagePicker.Candidate? {
        let candidates = lanes.map(\.candidate)
        guard let index = LanguagePicker.bestIndex(of: candidates) else { return nil }
        return candidates[index]
    }

    // DESIGN: Lane timestamps can place the same boundary word on opposite sides
    // of a cut. Remove a repeated suffix/prefix only when its audio ranges overlap;
    // genuinely repeated words at separate times must survive.
    static func removingBoundaryOverlap(_ tail: [SpeechToken], after head: [SpeechToken]) -> [SpeechToken] {
        for count in stride(from: min(head.count, tail.count), through: 1, by: -1) {
            let matches = zip(head.suffix(count), tail.prefix(count)).allSatisfy { left, right in
                let word = left.text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                let other = right.text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                let overlap = min(left.end, right.end) - max(left.start, right.start)
                let duration = min(left.end - left.start, right.end - right.start)
                return !word.isEmpty && String(String.UnicodeScalarView(word)).lowercased()
                    == String(String.UnicodeScalarView(other)).lowercased()
                    && duration > 0 && overlap >= duration / 2
            }
            if matches { return Array(tail.dropFirst(count)) }
        }
        return tail
    }

    static func joinTokens(_ tokens: [SpeechToken]) -> String {
        tokens.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func joinText(_ head: String, _ tail: String) -> String {
        var result = head
        appendText(tail, to: &result)
        return result
    }

    private static func appendText(_ tail: String, to head: inout String) {
        let tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return }
        if let last = head.unicodeScalars.last, let first = tail.unicodeScalars.first,
           isUnspaced(last) && isUnspaced(first) { head += tail; return }
        LiveTranscriber.append(tail, to: &head)
    }

    private static func isUnspaced(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value)
            || (0x0E00...0x0E7F).contains(scalar.value)
    }

    static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }
}
