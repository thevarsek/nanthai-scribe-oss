import Foundation

/// Only transcript-adjacent names enter replacement and Refine; the address book stays private.
public enum NameMatcher {
    public static func matches(in transcript: String, names: [String]) -> [DictionaryEntry] {
        let words = CorrectionDetector.tokens(transcript)
        var seen = Set<String>()
        var ranked: [(Double, DictionaryEntry)] = []
        for name in names {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            let count = CorrectionDetector.tokens(name).count
            guard count > 0, count <= words.count else { continue }
            var best: (score: Double, heard: String)?
            for index in 0...(words.count - count) {
                let heard = words[index..<(index + count)].joined(separator: " ")
                let score = CorrectionDetector.similarity(heard, name)
                if let heardKey = CorrectionDetector.phoneticKey(heard), let nameKey = CorrectionDetector.phoneticKey(name) {
                    guard heardKey == nameKey || score >= 0.75 else { continue }
                } else {
                    guard score >= 0.5 else { continue }
                }
                if best == nil || score > best!.score { best = (score, heard) }
            }
            if let best { ranked.append((best.score, DictionaryEntry(term: name, variants: [best.heard]))) }
        }
        return ranked.sorted { $0.0 == $1.0 ? $0.1.term < $1.1.term : $0.0 > $1.0 }.prefix(10).map(\.1)
    }
}
