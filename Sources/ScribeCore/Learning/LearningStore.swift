import Foundation
import Observation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Cross-process transactions prevent the keyboard from overwriting the app's review actions.
public struct LearningStore: Sendable {
    public struct Document: Codable, Equatable, Sendable {
        public var corrections = CorrectionLog()
        public var keyboard = KeyboardWords()
        public var pendingDictionary: [CorrectionPair] = []
        public init() {}
        public mutating func merge(_ incoming: Self) {
            corrections.merge(incoming.corrections)
            keyboard.merge(incoming.keyboard)
            var keys = Set(pendingDictionary.map(\.key))
            pendingDictionary += incoming.pendingDictionary.filter { keys.insert($0.key).inserted }
        }
    }
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> Document { try transaction { $0 } }

    public func transaction<T>(_ change: (inout Document) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appending(path: "learning.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { _ = flock(descriptor, LOCK_UN) }
        let url = directory.appending(path: "learning.json")
        var document = Document()
        if FileManager.default.fileExists(atPath: url.path) {
            document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        }
        let previous = document
        let result = try change(&document)
        if previous != document {
            try JSONEncoder().encode(document).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return result
    }
}

/// Observable review state is refreshed at foreground/appearance; no per-keystroke disk reads.
@MainActor
@Observable
public final class LearningModel {
    public let store: LearningStore
    public private(set) var document = LearningStore.Document()
    public private(set) var saveFailure: SaveFailure?

    public init(directory: URL) { store = LearningStore(directory: directory); reload() }
    public func reload() {
        do { document = try store.load(); saveFailure = nil }
        catch { saveFailure = SaveFailure("Couldn't open learning. Your saved words are kept.") }
    }
    @discardableResult
    public func update<T>(_ change: (inout LearningStore.Document) throws -> T) -> T? {
        do {
            let result = try store.transaction(change)
            document = try store.load(); saveFailure = nil
            return result
        } catch { saveFailure = SaveFailure("Couldn't save learning. Try again."); return nil }
    }
    public func record(_ pair: CorrectionPair, at now: Date = .now, canAsk: Bool) -> Bool {
        update { $0.corrections.record(pair, at: now, canAsk: canAsk) } ?? false
    }
    public func notNow(_ pair: CorrectionPair) { update { $0.corrections.notNow(pair) } }
    public func ignore(_ pair: CorrectionPair) { update { $0.corrections.ignore(pair) } }
    public func forget(_ pair: CorrectionPair) { update { $0.corrections.forget(pair) } }

    /// Queue acknowledgement follows the vocabulary write, so an interrupted merge can be replayed safely.
    @discardableResult
    public func add(_ pair: CorrectionPair, to vocabulary: Vocabulary) -> Bool {
        vocabulary.dictionary = pair.adding(to: vocabulary.dictionary)
        guard vocabulary.saveFailure == nil else { return false }
        forget(pair)
        return true
    }
    public func mergePending(into vocabulary: Vocabulary) {
        reload()
        for pair in document.pendingDictionary {
            guard add(pair, to: vocabulary) else { return }
            update { $0.pendingDictionary.removeAll { $0.key == pair.key } }
        }
    }
}
