import Foundation
import ScribeCore

public typealias DictationEntry = Note
public typealias HistoryRetention = NoteRetention

/// Local transcript storage. Applying the policy here keeps launch, insertion, and
/// setting changes consistent; Off omits untouched notes while keeping separate one-hour recovery.
public struct DictationHistory {
    public private(set) var deleted: [Note] = []
    public private(set) var entries: [DictationEntry]
    private let url: URL
    private let store: NoteStore
    private var retention: HistoryRetention
    private var needsReload = false
    // A failed load must remember whether Clear also included retained notes.
    private var pendingClear: Bool?
    public private(set) var unreadable: [UnreadableItem] = []
    public private(set) var saveFailure: SaveFailure?
    private var savedIDs: Set<UUID> = []
    private var recovery: LastDictationRecovery?
    public func recoverableDictation(at now: Date = .now) -> LastDictationRecovery? {
        guard let recovery, !recovery.isExpired(at: now) else { return nil }
        return recovery
    }
    public mutating func lastDictation(at now: Date = .now) -> LastDictationRecovery? {
        if recovery?.isExpired(at: now) == true {
            recovery = nil
            do { if FileManager.default.fileExists(atPath: lastURL.path) { try FileManager.default.removeItem(at: lastURL) } }
            catch { if saveFailure == nil { saveFailure = SaveFailure("Couldn't clear the last dictation.") } }
        }
        return recovery
    }
    private var lastURL: URL { url.deletingPathExtension().appendingPathExtension("last.json") }


    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "NanthAi Scribe", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    public init(url: URL = Self.defaultURL, retention: HistoryRetention, now: Date = .now) {
        self.url = url
        self.retention = retention
        store = NoteStore(root: url.deletingPathExtension().appendingPathExtension("notes"))
        entries = []
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                if data != Data("[]".utf8) {
                    try store.migrate(data)
                    try Data("[]".utf8).write(to: url, options: .atomic)
                }
            }
            try store.purgeDeleted(now: now)
            let loaded = try store.load()
            savedIDs = Set(loaded.notes.map(\.id))
            unreadable = loaded.unreadable
            deleted = loaded.notes.filter { $0.deletedAt != nil }
            entries = retention.prune(loaded.notes.filter { $0.deletedAt == nil }, now: now)
            recovery = (try? Data(contentsOf: lastURL)).flatMap { try? JSONDecoder().decode(LastDictationRecovery.self, from: $0) }
            if recovery?.isExpired(at: now) == true { recovery = nil; try? FileManager.default.removeItem(at: lastURL) }
            save()
        } catch { needsReload = true; saveFailure = SaveFailure("Couldn't save notes. Your changes are still here.") }
    }

    public mutating func insert(_ text: String, retention: HistoryRetention, now: Date = .now) {
        recovery = LastDictationRecovery(text: text, createdAt: now)
        if retention != .off { entries.insert(DictationEntry(date: now, text: text), at: 0) }
        prune(retention: retention, now: now)
    }

    public mutating func prune(retention: HistoryRetention, now: Date = .now) {
        self.retention = retention
        entries = retention.prune(entries, now: now)
        save()
    }

    public mutating func clear(includePinned: Bool = false) {
        if needsReload { pendingClear = (pendingClear ?? false) || includePinned }
        let now = Date.now
        deleted += entries.filter { includePinned || !$0.isRetained }.map { note in
            var note = note; note.deletedAt = now; note.modified = now; return note
        }
        entries.removeAll { includePinned || !$0.isRetained }
        save()
    }

    public mutating func importNotes(_ notes: [Note]) {
        let merged = BackupMerge.items(entries + deleted, notes, modified: { $0.modified })
        entries = merged.filter { $0.deletedAt == nil }; deleted = merged.filter { $0.deletedAt != nil }
        save()
    }
    public mutating func upsert(_ note: Note) {
        guard !deleted.contains(where: { $0.id == note.id }) else { return }
        if let index = entries.firstIndex(where: { $0.id == note.id }) { entries[index] = note }
        else { entries.insert(note, at: 0) }
        save()
    }

    public mutating func delete(_ id: UUID) {
        guard var note = entries.first(where: { $0.id == id }) else { return }
        note.deletedAt = .now; note.modified = .now
        deleted.append(note)
        entries.removeAll { $0.id == id }
        save()
    }
    public mutating func restore(_ id: UUID) {
        guard var note = deleted.first(where: { $0.id == id }) else { return }
        note.deletedAt = nil; note.modified = .now
        deleted.removeAll { $0.id == id }; entries.insert(note, at: 0); save()
    }
    public mutating func deleteNow(_ id: UUID) { deleted.removeAll { $0.id == id }; save() }


    public mutating func deleteUnreadable(_ id: UUID) {
        do { try store.delete(id); unreadable.removeAll { $0.id == id } }
        catch { if saveFailure == nil { saveFailure = SaveFailure("Couldn't delete this note.") } }
    }
    public mutating func retrySave() {
        if needsReload {
            let reloaded = DictationHistory(url: url, retention: retention)
            if !reloaded.needsReload {
                let current = Set((entries + deleted).map(\.id))
                for var note in reloaded.entries where !current.contains(note.id) {
                    if let includePinned = pendingClear, includePinned || !note.isRetained {
                        note.deletedAt = .now; note.modified = .now; deleted.append(note)
                    } else { entries.append(note) }
                }
                entries = retention.prune(entries, now: .now)
                savedIDs.formUnion(reloaded.savedIDs)
                let deletedIDs = Set(deleted.map(\.id))
                deleted += reloaded.deleted.filter { !deletedIDs.contains($0.id) }
                unreadable = reloaded.unreadable
                recovery = recovery ?? reloaded.recovery
                needsReload = false; pendingClear = nil
            }
        }
        save()
    }
    private mutating func save() {
        do {
            let all = entries + deleted
            let ids = Set(all.map(\.id))
            try store.save(all, removing: savedIDs.subtracting(ids))
            if !FileManager.default.fileExists(atPath: url.path) { try Data("[]".utf8).write(to: url, options: .atomic) }
            if let recovery { try JSONEncoder().encode(recovery).write(to: lastURL, options: .atomic) }
            savedIDs = ids
            if !needsReload { saveFailure = nil }
        } catch { if saveFailure == nil { saveFailure = SaveFailure("Couldn't save notes. Your changes are still here.") } }
    }
}
