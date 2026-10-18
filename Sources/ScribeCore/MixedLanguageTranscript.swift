import Foundation
import NaturalLanguage

/// Timed evidence from parallel recognizers. Text retains the recognizer's whitespace.
struct SpeechToken: Sendable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double

    var midpoint: Double { (start + end) / 2 }

    /// Result chunks need the same separator as the legacy string accumulator;
    /// whitespace inside one attributed result is already present in its runs.
    static func appending(_ tail: [SpeechToken], to head: [SpeechToken]) -> [SpeechToken] {
        guard let last = head.last, let first = tail.first else { return head + tail }
        var tail = tail
        let joined = LiveTranscriber.join(last.text, first.text)
        tail[0] = .init(text: String(joined.dropFirst(last.text.count)), start: first.start,
                        end: first.end, confidence: first.confidence)
        return head + tail
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

    mutating func apply(_ text: AttributedString, isFinal: Bool) {
        let segment = String(text.characters)
        let timed = LiveTranscriber.timedTokens(text)
        if isFinal {
            finalized = LiveTranscriber.join(finalized, segment)
            volatile = ""
            tokens = SpeechToken.appending(timed.tokens, to: tokens)
            hasTiming = hasTiming && timed.complete
            volatileTokens = []
            volatileHasTiming = true
            for run in text.runs {
                if let confidence = run.transcriptionConfidence {
                    confidenceSum += confidence
                    confidenceCount += 1
                }
            }
        } else {
            volatile = segment
            // DESIGN: Apple reports zero confidence for volatile segments (one coarse
            // range, not word ranges). A neutral live-only prior lets NL discriminate;
            // finalized scores always use the recognizer's actual confidence.
            volatileTokens = timed.tokens.map {
                SpeechToken(text: $0.text, start: $0.start, end: $0.end,
                            confidence: $0.confidence > 0 ? $0.confidence : 0.5)
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
/// All state belongs to one utterance; final selection is independent of live hysteresis.
struct MixedLanguageTranscript {
    struct Window {
        let start: Double
        let end: Double
        let candidates: [LanguagePicker.Candidate]
        let tokens: [[SpeechToken]]
        let scores: [Double]
        let wordCount: Int
        let isFinal: Bool
        var winner: Int
    }

    private(set) var volatileText = ""
    private var previous: [Window] = []
    private var tailLane: Int
    private var challenger: Int?
    private var challengerUpdates = 0

    init(displayIndex: Int = 0) { tailLane = displayIndex }

    static func finalSelection(lanes: [SpeechLane], batch: [LanguagePicker.Candidate]) -> LanguagePicker.Candidate? {
        let candidates = lanes.map(\.candidate) + batch
        guard let best = LanguagePicker.bestIndex(of: candidates) else { return nil }
        // Batch engines have no word timeline and remain whole-utterance candidates.
        guard best < lanes.count, lanes.count > 1 else { return candidates[best] }
        var selector = MixedLanguageTranscript()
        return selector.select(lanes, live: false)
    }

    mutating func select(_ lanes: [SpeechLane], live: Bool) -> LanguagePicker.Candidate? {
        volatileText = ""
        guard lanes.count > 1 else {
            volatileText = lanes.first?.volatile.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
            words += Self.wordCount(token.text)
            let punctuation = token.text.trimmingCharacters(in: .whitespacesAndNewlines).last
            let sentenceEnd = punctuation.map { ".!?。！？".contains($0) } ?? false
            if (next.start - token.end >= 0.35 || sentenceEnd),
               token.end - cuts.last! >= 1.2 || words >= 3 {
                cuts.append((token.end + next.start) / 2)
                words = 0
            }
        }
        cuts.append(end)
        // A coarse volatile range cannot be assigned to one of the finalized word
        // windows it spans. Merge those windows until timing arrives, rather than
        // freezing the previous preview for the rest of an uninterrupted sentence.
        if live {
            let coarse = lanes.flatMap(\.volatileTokens).filter { Self.wordCount($0.text) > 1 }
            cuts = cuts.enumerated().filter { index, cut in
                index == 0 || index == cuts.count - 1 || !coarse.contains { $0.start < cut && $0.end > cut }
            }.map(\.element)
        }
        var windows: [Window] = []
        for index in 0..<(cuts.count - 1) {
            let lower = cuts[index], upper = cuts[index + 1]
            let windowTokens = evidence.map { tokens in
                tokens.filter { $0.midpoint >= lower && ($0.midpoint < upper || index == cuts.count - 2) }
            }
            let candidates = lanes.indices.map { lane in
                let tokens = windowTokens[lane]
                return LanguagePicker.Candidate(locale: lanes[lane].locale,
                    text: Self.joinTokens(tokens),
                    confidence: tokens.isEmpty ? 0 : tokens.map(\.confidence).reduce(0, +) / Double(tokens.count))
            }
            let isFinal = lanes.allSatisfy { lane in
                !lane.volatileTokens.contains { $0.midpoint >= lower && $0.midpoint <= upper }
                    && (lane.tokens.last?.end ?? -.infinity) >= min(upper, end) - 0.2
            }
            let scores = candidates.map { $0.text.isEmpty ? 0 : LanguagePicker.score($0, among: languages) }
            let winner = candidates.indices.filter { !candidates[$0].text.isEmpty }
                .max(by: { scores[$0] < scores[$1] }) ?? 0
            windows.append(.init(start: lower, end: upper, candidates: candidates, tokens: windowTokens, scores: scores,
                                 wordCount: candidates.map { Self.wordCount($0.text) }.max() ?? 0, isFinal: isFinal, winner: winner))
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
        if live, !windows.isEmpty {
            for index in windows.indices.dropLast() {
                if let old = previous.first(where: {
                    let overlap = min($0.end, windows[index].end) - max($0.start, windows[index].start)
                    return $0.isFinal && overlap >= 0.8 * max($0.end - $0.start, windows[index].end - windows[index].start)
                }), !windows[index].candidates[old.winner].text.isEmpty,
                   windows[index].scores[windows[index].winner] - windows[index].scores[old.winner] < 0.25 {
                    windows[index].winner = old.winner
                }
            }
            let last = windows.count - 1
            let proposed = windows[last].winner
            if windows[last].isFinal {
                tailLane = proposed
                challenger = nil
                challengerUpdates = 0
            } else if proposed != tailLane,
               windows[last].scores[proposed] - windows[last].scores[tailLane] >= 0.15 {
                challengerUpdates = challenger == proposed ? challengerUpdates + 1 : 1
                challenger = proposed
                if challengerUpdates >= 2 { tailLane = proposed; challenger = nil; challengerUpdates = 0 }
            } else { challenger = nil; challengerUpdates = 0 }
            windows[last].winner = tailLane
            previous = windows
        }
        var text = ""
        var finalizedPrefix = ""
        var hasVolatile = false
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
            let beforeWindow = text
            text = Self.joinText(text, Self.joinTokens(tokens))
            if !hasVolatile {
                let volatile = lanes[window.winner].volatileTokens
                let finalized = tokens.prefix { token in
                    !volatile.contains { $0.start == token.start && $0.end == token.end }
                }
                finalizedPrefix = Self.joinText(beforeWindow, Self.joinTokens(Array(finalized)))
                hasVolatile = finalized.count != tokens.count
            }
            emitted += tokens
            lastWinner = window.winner
            durations[window.winner] += window.end - window.start
        }
        volatileText = String(text.dropFirst(finalizedPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        let dominant = durations.indices.max(by: { durations[$0] < durations[$1] }) ?? 0
        let selection = LanguagePicker.Candidate(locale: lanes[dominant].locale, text: text, confidence: 0)
        return selection
    }

    private mutating func wholeLaneSelection(_ lanes: [SpeechLane]) -> LanguagePicker.Candidate? {
        let candidates = lanes.map(\.candidate)
        guard let index = LanguagePicker.bestIndex(of: candidates) else { return nil }
        volatileText = lanes[index].volatile.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return head }
        if let first = tail.first, ",.!?;:，。！？、；：)]}’”".contains(first) { return head + tail }
        // Unspaced scripts retain the recognizer's word boundaries.
        if let last = head.unicodeScalars.last, let first = tail.unicodeScalars.first,
           isUnspaced(last) && isUnspaced(first) { return head + tail }
        return LiveTranscriber.join(head, tail)
    }

    private static func isUnspaced(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value)
            || (0x0E00...0x0E7F).contains(scalar.value)
    }

    private static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }
}
