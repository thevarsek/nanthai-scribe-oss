import Foundation

public enum DictionaryReplacement {
    private struct Match {
        let range: NSRange
        let term: String
        let order: Int
    }

    /// Match only original input: a replacement can never trigger another dictionary entry.
    public static func apply(to text: String, dictionary: [DictionaryEntry]) -> String {
        var matches: [Match] = []
        for (order, entry) in dictionary.enumerated() {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            for variant in entry.variants + [term] {
                let words = variant.split(whereSeparator: \.isWhitespace)
                guard !words.isEmpty else { continue }
                let pattern = words.map { word in
                    word.map { character in
                        let composed = String(character).precomposedStringWithCanonicalMapping
                        let decomposed = composed.decomposedStringWithCanonicalMapping
                        let escaped = NSRegularExpression.escapedPattern(for: composed)
                        return composed.utf16.elementsEqual(decomposed.utf16) ? escaped
                            : "(?:" + escaped + "|" + NSRegularExpression.escapedPattern(for: decomposed) + ")"
                    }.joined()
                }.joined(separator: #"\s+"#)
                // Combining marks belong to their letter, including decomposed Italian accents.
                guard let regex = try? NSRegularExpression(
                    pattern: #"(?<![\p{L}\p{N}\p{M}])"# + pattern + #"(?![\p{L}\p{N}\p{M}])"#,
                    options: .caseInsensitive) else { continue }
                matches += regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                    Match(range: $0.range, term: term, order: order)
                }
            }
        }
        // Resolve overlaps globally by length, then entry order; render in input order.
        matches.sort {
            if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.range.location < $1.range.location
        }
        var selected: [Match] = []
        for match in matches where !selected.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
            selected.append(match)
        }
        let original = text as NSString
        var output = ""
        var cursor = 0
        for match in selected.sorted(by: { $0.range.location < $1.range.location }) {
            output += original.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += match.term
            cursor = NSMaxRange(match.range)
        }
        return output + original.substring(from: cursor)
    }
}
