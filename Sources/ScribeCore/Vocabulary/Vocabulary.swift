import Foundation
import Observation

/// One local file owns words and snippets, ready for future sync without platform paths.
@MainActor
@Observable
public final class Vocabulary {
    public struct Document: Codable, Equatable, Sendable {
        public var dictionary: [DictionaryEntry]
        public var snippets: [Snippet]

        public init(dictionary: [DictionaryEntry] = [], snippets: [Snippet] = []) {
            self.dictionary = dictionary
            self.snippets = snippets
        }
    }

    private var document: Document
    private var loadFailed = false

    public var dictionary: [DictionaryEntry] {
        get { document.dictionary }
        set {
            guard newValue != document.dictionary else { return }
            let previous = Dictionary(document.dictionary.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var updated = newValue
            for index in updated.indices {
                if let old = previous[updated[index].id], old != updated[index] {
                    updated[index].modified = .now
                }
            }
            loadFailed = false
            document.dictionary = updated
            save()
        }
    }
    public var snippets: [Snippet] {
        get { document.snippets }
        set {
            guard newValue != document.snippets else { return }
            let previous = Dictionary(document.snippets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var updated = newValue
            for index in updated.indices {
                if let old = previous[updated[index].id], old != updated[index] {
                    updated[index].modified = .now
                }
            }
            loadFailed = false
            document.snippets = updated
            save()
        }
    }
    public func mergeBackup(dictionary: [DictionaryEntry], snippets: [Snippet]) {
        document.dictionary = BackupMerge.items(document.dictionary, dictionary, modified: { $0.modified })
        document.snippets = BackupMerge.items(document.snippets, snippets, modified: { $0.modified })
        save()
    }
    public private(set) var saveFailure: SaveFailure?
    /// A failed read must be retried before an empty fallback document can be written.
    public func retrySave() {
        guard loadFailed else { save(); return }
        let reloaded = Vocabulary(directory: fileURL.deletingLastPathComponent(), legacyDefaults: legacyDefaults)
        guard reloaded.persistenceError == nil else { persistenceError = reloaded.persistenceError; return }
        document = reloaded.document
        loadFailed = false
        persistenceError = nil
        saveFailure = nil
    }
    public private(set) var persistenceError: (any Error)?
    public let fileURL: URL
    private let legacyDefaults: UserDefaults?

    public init(directory: URL, legacyDefaults: UserDefaults? = nil, migrationDate: Date = .now) {
        fileURL = directory.appending(path: "vocabulary.json")
        self.legacyDefaults = legacyDefaults
        let decoder = JSONDecoder()
        decoder.userInfo[.vocabularyMigrationDate] = migrationDate
        var document = Document()
        var shouldMigrate = false
        var loadError: (any Error)?
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                document = try decoder.decode(Document.self, from: Data(contentsOf: fileURL))
            } else {
                if let data = legacyDefaults?.data(forKey: "snippets") {
                    document.snippets = try decoder.decode([Snippet].self, from: data)
                }
                shouldMigrate = true
            }
        } catch { loadError = error }
        self.document = document
        persistenceError = loadError
        loadFailed = loadError != nil
        if loadError != nil { saveFailure = SaveFailure("Couldn't open Dictionary and Snippets.") }
        if shouldMigrate { save() }
    }

    /// A failed migration keeps the legacy key until a complete atomic write succeeds.
    private func save() {
        do {
            try write()
            legacyDefaults?.removeObject(forKey: "snippets")
            persistenceError = nil
            saveFailure = nil
        } catch {
            persistenceError = error
            if saveFailure == nil { saveFailure = SaveFailure("Couldn't save Dictionary and Snippets. Your changes are still here.") }
        }
    }

    private func write() throws {
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
