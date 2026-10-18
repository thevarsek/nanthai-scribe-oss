import Foundation

public struct DictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable { case user, learned }

    public var id: UUID
    public var term: String
    public var variants: [String]
    public var source: Source
    public var modified: Date

    public init(id: UUID = UUID(), term: String = "", variants: [String] = [],
                source: Source = .user, modified: Date = .now) {
        self.id = id
        self.term = term
        self.variants = variants
        self.source = source
        self.modified = modified
    }

    /// Both editors use the same normalization, preserving the first spelling entered.
    public static func parseVariants(_ text: String, term: String) -> [String] {
        var seen = Set([caseKey(term.trimmingCharacters(in: .whitespacesAndNewlines))])
        return text.split(separator: ",").compactMap { part in
            let variant = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !variant.isEmpty, seen.insert(caseKey(variant)).inserted else { return nil }
            return variant
        }
    }

    public static func terms(in entries: [Self]) -> [String] {
        entries.map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Speech bias has a bounded context; personal spellings get priority over screen text.
    public static func contextualStrings(in entries: [Self], screenTerms: [String] = []) -> [String] {
        var seen = Set<String>()
        return Array((terms(in: entries) + screenTerms).filter {
            seen.insert(caseKey($0)).inserted
        }.prefix(100))
    }

    private static func caseKey(_ text: String) -> String {
        text.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}
