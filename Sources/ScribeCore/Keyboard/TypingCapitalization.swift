import Foundation

public enum TypingCapitalization {
    public enum Mode: Sendable, Equatable { case none, words, sentences, allCharacters }

    public static func shouldCapitalize(before: String?, mode: Mode) -> Bool {
        switch mode {
        case .none: return false
        case .allCharacters: return true
        case .words: return before?.last.map(\.isWhitespace) ?? true
        case .sentences:
            guard let before, !before.isEmpty else { return true }
            if before.last == "\n" { return true }
            guard before.last?.isWhitespace == true else { return false }
            let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.last.map { ".!?".contains($0) } == true
        }
    }
}
