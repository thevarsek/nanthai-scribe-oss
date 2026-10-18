import Foundation
import NaturalLanguage

public struct CorrectionPair: Codable, Equatable, Hashable, Sendable {
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) { self.heard = heard; self.meant = meant }
    public var key: String { heard.precomposedStringWithCanonicalMapping.lowercased() + "\u{0}" + meant.precomposedStringWithCanonicalMapping.lowercased() }

    /// Extending a term preserves its variants and marks the newly learned spelling.
    public func adding(to dictionary: [DictionaryEntry], at now: Date = .now) -> [DictionaryEntry] {
        var result = dictionary
        if let index = result.firstIndex(where: { $0.term.caseInsensitiveCompare(meant) == .orderedSame }) {
            let variants = result[index].variants + [heard]
            result[index].term = meant
            result[index].variants = DictionaryEntry.parseVariants(variants.joined(separator: ","), term: meant)
            result[index].source = .learned
            result[index].modified = now
            let learned = result.remove(at: index)
            result.insert(learned, at: 0)
        } else {
            result.insert(DictionaryEntry(term: meant, variants: [heard], source: .learned, modified: now), at: 0)
        }
        // The explicit new spelling wins ties with an older canonical spelling of what was heard.
        return result
    }
}

/// Separator-only matches do not split a replaced phrase into several corrections.
public enum CorrectionDetector {
    public static func candidate(inserted: String, current: String, dictionary: [DictionaryEntry] = []) -> CorrectionPair? {
        var runs: [(String, String)] = []
        var old = "", new = ""
        func flush() {
            if !old.isEmpty || !new.isEmpty { runs.append((old, new)) }
            old = ""; new = ""
        }
        for segment in NoteDiff.segments(original: inserted, current: current) {
            switch segment.kind {
            case .unchanged:
                if segment.text.contains(where: { $0.isLetter || $0.isNumber }) { flush() }
                else {
                    if !old.isEmpty { old += segment.text }
                    if !new.isEmpty { new += segment.text }
                }
            case .removed:
                old += segment.text
            case .inserted:
                new += segment.text
            case .gap: break
            }
        }
        flush()
        let words = runs.filter {
            $0.0.filter { $0.isLetter || $0.isNumber } != $0.1.filter { $0.isLetter || $0.isNumber }
        }
        guard words.count == 1 else { return nil }
        let (before, after) = words[0]
        guard !before.contains(where: \.isNumber), !after.contains(where: \.isNumber) else { return nil }
        let oldWords = tokens(before), newWords = tokens(after)
        guard (1...3).contains(oldWords.count), (1...3).contains(newWords.count) else { return nil }
        let heard = oldWords.joined(separator: " "), meant = newWords.joined(separator: " ")
        guard heard != meant else { return nil }
        let name = meant.first?.isUppercase == true && heard.first?.isUppercase != true
        guard name || similar(heard, meant) else { return nil }
        guard !dictionary.contains(where: { entry in
            entry.term == meant &&
                (entry.variants + [entry.term]).contains { $0.caseInsensitiveCompare(heard) == .orderedSame }
        }) else { return nil }
        return CorrectionPair(heard: heard, meant: meant)
    }

    static func tokens(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
            .filter { $0.contains(where: \.isLetter) }
    }

    static func letters(_ text: String) -> String {
        String(text.precomposedStringWithCanonicalMapping.lowercased().filter(\.isLetter))
    }

    static func similar(_ lhs: String, _ rhs: String) -> Bool {
        similarity(lhs, rhs) >= 0.5 || (phoneticKey(lhs).map { $0 == phoneticKey(rhs) } ?? false)
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(letters(lhs)), b = Array(letters(rhs))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var row = [i + 1]
            for (j, y) in b.enumerated() { row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (x == y ? 0 : 1))) }
            previous = row
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }

    /// A compact Latin phonetic key, with no English-only tokenizer or transliteration of other scripts.
    static func phoneticKey(_ text: String) -> String? {
        let raw = letters(text).folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        guard !raw.isEmpty, raw.unicodeScalars.allSatisfy({ (97...122).contains($0.value) }) else { return nil }
        var key = raw
        for (from, to) in [("ph", "f"), ("kn", "n"), ("wr", "r"), ("sch", "sh"), ("ch", "sh"), ("sh", "s"),
                           ("ce", "se"), ("ci", "si"), ("cy", "sy"), ("ck", "k"), ("qu", "k"), ("c", "k"), ("q", "k"), ("x", "ks"), ("z", "s"), ("v", "f")] {
            key = key.replacingOccurrences(of: from, with: to)
        }
        var result = ""
        for (index, letter) in key.enumerated() {
            if index > 0, "aeiouyhw".contains(letter) { continue }
            if result.last != letter { result.append(letter) }
        }
        return result.isEmpty ? nil : result
    }
}
