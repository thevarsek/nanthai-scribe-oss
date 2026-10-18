import Foundation

/// Token ranges preserve the original spelling and whitespace outside each replacement.
public enum Snippets {
    private struct Word {
        var value: String
        var range: Range<String.Index>
    }

    private struct Candidate {
        var order: Int
        var snippet: Snippet
        var tokens: [String]
    }

    private static func words(_ text: String) -> [Word] {
        var result: [Word] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isLetter || text[index].isNumber {
                if start == nil { start = index }
            } else if let beginning = start {
                result.append(Word(value: String(text[beginning..<index]).lowercased(), range: beginning..<index))
                start = nil
            }
        }
        if let start { result.append(Word(value: String(text[start...]).lowercased(), range: start..<text.endIndex)) }
        return result
    }

    public static func exactMatch(in text: String, snippets: [Snippet]) -> String? {
        let tokens = words(text).map(\.value)
        guard !tokens.isEmpty else { return nil }
        return snippets.first { words($0.trigger).map(\.value) == tokens }?.text
    }

    public static func expand(in text: String, snippets: [Snippet]) -> String {
        let tokens = words(text)
        // DESIGN: Overlaps prefer the longest trigger, then list order; expansions never recurse.
        let candidates: [Candidate] = snippets.enumerated().map { index, snippet in
            Candidate(order: index, snippet: snippet, tokens: words(snippet.trigger).map(\.value))
        }.filter { !$0.tokens.isEmpty }.sorted { left, right in
            left.tokens.count == right.tokens.count ? left.order < right.order : left.tokens.count > right.tokens.count
        }
        var output = ""
        var cursor = text.startIndex
        var index = 0
        while index < tokens.count {
            if let match = candidates.first(where: { candidate in
                let end = index + candidate.tokens.count
                return end <= tokens.count && Array(tokens[index..<end].map(\.value)) == candidate.tokens
            }) {
                let end = index + match.tokens.count
                output += text[cursor..<tokens[index].range.lowerBound]
                output += match.snippet.text
                cursor = tokens[end - 1].range.upperBound
                index = end
            } else { index += 1 }
        }
        output += text[cursor...]
        return output
    }
}
