import Foundation
import NaturalLanguage

/// Tokenizer boundaries support scripts without spaces; separator tokens preserve exact text.
public enum NoteDiff {
    /// `gap` is display-only spacing; it belongs to neither version.
    public enum Kind: Sendable { case unchanged, inserted, removed, gap }
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let kind: Kind
    }

    public static func segments(original: String, current: String) -> [Segment] {
        let old = tokens(original), new = tokens(current)
        let difference = new.difference(from: old)
        let removed = Set(difference.removals.map(\.offset))
        let inserted = Set(difference.insertions.map(\.offset))
        let oldKept = old.indices.filter { !removed.contains($0) }
        let newKept = new.indices.filter { !inserted.contains($0) }
        var result: [Segment] = []
        // Shared separators match as unchanged, so a replaced word can sit flush against its
        // replacement ("notesto"). In scripts with spaces, a display-only gap separates them.
        let spaced = original.contains(" ") || current.contains(" ")
        func append(_ text: String, _ kind: Kind) {
            guard !text.isEmpty else { return }
            if spaced, kind == .inserted, let last = result.last, last.kind == .removed,
               last.text.last?.isWhitespace == false, text.first?.isWhitespace == false {
                result.append(Segment(text: " ", kind: .gap))
            }
            if let last = result.last, last.kind == kind {
                result[result.count - 1] = Segment(text: last.text + text, kind: kind)
            } else { result.append(Segment(text: text, kind: kind)) }
        }
        var oldIndex = 0, newIndex = 0
        for (oldMatch, newMatch) in zip(oldKept, newKept) {
            while oldIndex < oldMatch { append(old[oldIndex], .removed); oldIndex += 1 }
            while newIndex < newMatch { append(new[newIndex], .inserted); newIndex += 1 }
            append(new[newMatch], .unchanged)
            oldIndex = oldMatch + 1
            newIndex = newMatch + 1
        }
        while oldIndex < old.count { append(old[oldIndex], .removed); oldIndex += 1 }
        while newIndex < new.count { append(new[newIndex], .inserted); newIndex += 1 }
        return result
    }

    private static func tokens(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [String] = []
        var cursor = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if cursor < range.lowerBound { result.append(String(text[cursor..<range.lowerBound])) }
            result.append(String(text[range]))
            cursor = range.upperBound
            return true
        }
        if cursor < text.endIndex { result.append(String(text[cursor...])) }
        return result
    }
}

private extension CollectionDifference.Change {
    var offset: Int {
        switch self { case .insert(let offset, _, _), .remove(let offset, _, _): offset }
    }
}
