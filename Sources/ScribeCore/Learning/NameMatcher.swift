import Foundation
import NaturalLanguage

/// Only transcript-adjacent names enter replacement and Refine; the address book stays private.
///
/// A contact name may only replace something that isn't already a real word: "and" must never
/// become "Andy" just because the two sound alike. Replacement is case-insensitive and applies
/// to every occurrence, so a heard span qualifies only if all of its occurrences do.
public enum NameMatcher {
    /// - Parameter isWord: whether a lowercased word is an ordinary word in one of the dictation
    ///   languages. Callers pass the platform spell checker; ScribeCore has no lexicon of its own.
    public static func matches(in transcript: String, names: [String],
                               isWord: (String) -> Bool = { _ in false }) -> [DictionaryEntry] {
        let words = Word.split(transcript)
        guard !words.isEmpty else { return [] }
        let folded = words.map { $0.text.lowercased() }
        let function = functionWords(in: transcript, words: words)
        let ordinary = folded.map(isWord)
        var seen = Set<String>()
        var ranked: [(Double, DictionaryEntry)] = []
        for name in names {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            let nameWords = CorrectionDetector.tokens(name).map { $0.lowercased() }
            let count = nameWords.count
            guard count > 0, count <= words.count else { continue }
            /// A word is a name candidate when it is neither a function word nor an ordinary word,
            /// unless the recogniser capitalised it mid-sentence. A word spelt exactly like the
            /// name's own word ("de" in "De Luca") rides along but can't qualify a span alone.
            func standsAlone(_ index: Int) -> Bool {
                !function[index] && (!ordinary[index] || words[index].isProperNoun)
            }
            func fits(_ start: Int) -> Bool {
                var alone = false
                for offset in 0..<count {
                    if standsAlone(start + offset) { alone = true }
                    else if folded[start + offset] != nameWords[offset] { return false }
                }
                return alone
            }
            var best: (score: Double, heard: String)?
            var checked = Set<String>()
            for index in 0...(words.count - count) {
                let key = folded[index..<(index + count)].joined(separator: " ")
                guard checked.insert(key).inserted else { continue }
                let heard = words[index..<(index + count)].map(\.text).joined(separator: " ")
                let score = CorrectionDetector.similarity(heard, name)
                guard sounds(heard, like: name, score: score) else { continue }
                let occurrences = (0...(words.count - count)).filter {
                    folded[$0..<($0 + count)].joined(separator: " ") == key
                }
                guard occurrences.allSatisfy(fits) else { continue }
                if best == nil || score > best!.score { best = (score, heard) }
            }
            if let best { ranked.append((best.score, DictionaryEntry(term: name, variants: [best.heard]))) }
        }
        return ranked.sorted { $0.0 == $1.0 ? $0.1.term < $1.1.term : $0.0 > $1.0 }.prefix(10).map(\.1)
    }

    /// Same sound and at least half the letters, or one slip in seven letters with the same first
    /// letter. Scripts without a phonetic key need close spelling.
    static func sounds(_ heard: String, like name: String, score: Double) -> Bool {
        guard let heardKey = soundKey(heard), let nameKey = soundKey(name) else { return score >= 0.75 }
        if heardKey == nameKey { return score >= 0.5 }
        return score >= 0.85 && heardKey.first == nameKey.first
    }

    /// Italian "gi" before a vowel is the English "j": Giulia and Julia sound the same.
    private static func soundKey(_ text: String) -> String? {
        let letters = CorrectionDetector.letters(text)
        let softened = letters.replacing(/gi([aeiouàèéìòù])/) { "j" + $0.output.1 }
        return CorrectionDetector.phoneticKey(softened)
    }

    /// Pronouns, articles, prepositions, conjunctions and particles, by the system tagger, which
    /// covers many languages without a word list here. Interjections are left out: the tagger
    /// files unknown lowercase names such as "nicolo" there.
    private static func functionWords(in transcript: String, words: [Word]) -> [Bool] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = transcript
        let closed: Set<NLTag> = [.pronoun, .determiner, .preposition, .conjunction, .particle]
        return words.map { word in
            let (tag, _) = tagger.tag(at: word.range.lowerBound, unit: .word, scheme: .lexicalClass)
            return tag.map(closed.contains) ?? false
        }
    }

    private struct Word {
        let text: String
        let range: Range<String.Index>
        /// Capitalised by the recogniser somewhere a sentence can't start.
        let isProperNoun: Bool

        static func split(_ transcript: String) -> [Word] {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = transcript
            return tokenizer.tokens(for: transcript.startIndex..<transcript.endIndex).compactMap { range in
                let text = String(transcript[range])
                guard text.contains(where: \.isLetter) else { return nil }
                let before = transcript[..<range.lowerBound].reversed().drop { " \t\"'“”‘’«»(".contains($0) }
                let opensSentence = before.first.map { ".!?…:\n\r¿¡".contains($0) } ?? true
                return Word(text: text, range: range, isProperNoun: text.first?.isUppercase == true && !opensSentence)
            }
        }
    }
}
