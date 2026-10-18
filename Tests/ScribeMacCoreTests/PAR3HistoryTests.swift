import Foundation
import ScribeCore
import Testing
@testable import ScribeMacCore

@Suite struct PAR3HistoryTests {
    @Test func deleteRestoreAndPurgeSurviveRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PAR3-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.json")
        var history = DictationHistory(url: file, retention: .forever)
        let note = Note(text: "edited", origin: .typed, isKept: true, pinned: true, original: "original")
        history.upsert(note); history.delete(note.id)
        #expect(history.entries.isEmpty)
        #expect(history.deleted.first?.original == "original")
        var reloaded = DictationHistory(url: file, retention: .off)
        #expect(reloaded.entries.isEmpty)
        #expect(reloaded.deleted.count == 1)
        reloaded.upsert(note) // An editor's delayed autosave must not resurrect a deleted item.
        #expect(reloaded.entries.isEmpty)
        reloaded.restore(note.id)
        #expect(reloaded.entries.first?.pinned == true)
        #expect(reloaded.entries.first?.text == "edited")
        #expect(reloaded.entries.first?.original == "original")
        reloaded.delete(note.id); reloaded.deleteNow(note.id)
        #expect(DictationHistory(url: file, retention: .forever).deleted.isEmpty)
        history = DictationHistory(url: file, retention: .forever)
        history.upsert(note); history.delete(note.id)
        #expect(DictationHistory(url: file, retention: .forever, now: .now.addingTimeInterval(31 * 86_400)).deleted.isEmpty)
    }
    @Test func retentionExpiryBypassesBinAndImportPreservesNewerTombstones() {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PAR3-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var history = DictationHistory(url: directory.appending(path: "history.json"), retention: .forever)
        history.insert("old", retention: .forever, now: .now.addingTimeInterval(-2 * 86_400))
        history.prune(retention: .oneDay)
        #expect(history.entries.isEmpty && history.deleted.isEmpty)
        let note = Note(text: "kept", origin: .typed)
        history.upsert(note); history.delete(note.id); history.importNotes([note])
        #expect(history.entries.isEmpty && history.deleted.count == 1)
    }
}
