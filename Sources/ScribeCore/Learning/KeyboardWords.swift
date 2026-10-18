import Foundation

public struct KeyboardWords: Codable, Equatable, Sendable {
    public struct Word: Codable, Equatable, Identifiable, Sendable {
        public var id: String { text.lowercased() }
        public let text: String
        public var keeps: Int
        public var modified: Date?
    }
    public private(set) var observations: [Word] = []
    public init() {}
    public var words: [String] { observations.filter { $0.keeps >= 2 }.map(\.text).sorted() }

    /// The first keep still protects the current session; only a repeated keep persists acceptance.
    @discardableResult
    public mutating func keep(_ word: String) -> Bool {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return false }
        if let index = observations.firstIndex(where: { $0.id == word.lowercased() }) {
            observations[index].keeps += 1
            observations[index].modified = .now
            return observations[index].keeps == 2
        }
        observations.append(Word(text: word, keeps: 1, modified: .now))
        return false
    }
    public mutating func add(_ word: String) {
        remove(word)
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        if !word.isEmpty { observations.append(Word(text: word, keeps: 2, modified: .now)) }
    }
    public mutating func remove(_ word: String) { observations.removeAll { $0.id == word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } }
    public mutating func merge(_ other: Self) {
        observations = BackupMerge.items(observations, other.observations, modified: { $0.modified ?? .distantPast })
    }
    public mutating func reset() { observations.removeAll() }
}
