import Foundation
import Testing
@testable import ScribeCore

@MainActor
@Suite struct VocabularyTests {
    @Test func roundTripAndWriteThroughModifiedDates() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Vocabulary(directory: root)
        let old = Date(timeIntervalSince1970: 1)
        store.dictionary = [DictionaryEntry(term: "Niccolò", variants: ["nicolo"], source: .learned, modified: old)]
        store.snippets = [Snippet(trigger: "signature", text: "Best,\nAlex", modified: old)]
        store.dictionary[0].term = "Società"
        store.snippets[0].text = "New signature"
        #expect(store.dictionary[0].modified > old)
        #expect(store.snippets[0].modified > old)
        let restored = Vocabulary(directory: root)
        #expect(restored.dictionary == store.dictionary)
        #expect(restored.snippets == store.snippets)
        #expect(restored.persistenceError == nil)
        store.dictionary.removeAll()
        #expect(Vocabulary(directory: root).dictionary.isEmpty)
        #expect(!Vocabulary(directory: root).snippets.isEmpty)
    }

    @Test func oldSnippetDecodesWithoutModifiedAndMigratesOnlyOnce() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "VocabularyTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let id = UUID()
        let data = Data("[{\"id\":\"\(id)\",\"trigger\":\"signature\",\"text\":\"Verbatim\"}]".utf8)
        #expect(try JSONDecoder().decode([Snippet].self, from: data).first?.text == "Verbatim")
        defaults.set(data, forKey: "snippets")
        let date = Date(timeIntervalSince1970: 1234)
        let store = Vocabulary(directory: root, legacyDefaults: defaults, migrationDate: date)
        #expect(store.snippets == [Snippet(id: id, trigger: "signature", text: "Verbatim", modified: date)])
        #expect(defaults.data(forKey: "snippets") == nil)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        defaults.set(try JSONEncoder().encode([Snippet(trigger: "stale")]), forKey: "snippets")
        #expect(Vocabulary(directory: root, legacyDefaults: defaults).snippets == store.snippets)
    }

    @Test func failedMigrationKeepsLegacyKeyAndCanRetry() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "VocabularyTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        try Data().write(to: root)
        let snippets = [Snippet(trigger: "signature", text: "Preserved")]
        let data = try JSONEncoder().encode(snippets)
        defaults.set(data, forKey: "snippets")
        let store = Vocabulary(directory: root, legacyDefaults: defaults)
        #expect(store.persistenceError != nil)
        #expect(store.snippets == snippets)
        #expect(defaults.data(forKey: "snippets") == data)
        try FileManager.default.removeItem(at: root)
        store.dictionary = [DictionaryEntry(term: "NanthAi")]
        #expect(store.persistenceError == nil)
        #expect(defaults.data(forKey: "snippets") == nil)
        #expect(Vocabulary(directory: root).snippets == snippets)
    }
}
