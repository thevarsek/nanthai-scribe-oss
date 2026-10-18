import Foundation
import Testing
@testable import ScribeMacCore

@Suite struct ParityRecoveryTests {
    @Test func lastDictationSurvivesHistoryOffAndRelaunchThenExpires() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "history.json")
        let now = Date.now
        var history = DictationHistory(url: url, retention: .off, now: now)
        history.insert("Synthetic last dictation", retention: .off, now: now)
        #expect(history.entries.isEmpty)
        var reopened = DictationHistory(url: url, retention: .off, now: now)
        let kept = reopened.lastDictation(at: now)
        let expired = reopened.lastDictation(at: now.addingTimeInterval(3_600))
        #expect(kept?.text == "Synthetic last dictation")
        #expect(expired == nil)
        #expect(!FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("last.json").path))
    }
    @Test func failedSavesKeepChangesAndOneFailureIdentityUntilSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appending(path: "blocked")
        try Data().write(to: blocker)
        var history = DictationHistory(url: blocker.appending(path: "history.json"), retention: .forever)
        history.insert("Synthetic text", retention: .forever)
        let first = history.saveFailure?.id
        history.retrySave()
        #expect(history.entries.first?.text == "Synthetic text")
        #expect(history.saveFailure?.id == first)
        try FileManager.default.removeItem(at: blocker)
        history.retrySave()
        #expect(history.saveFailure == nil)
        #expect(DictationHistory(url: blocker.appending(path: "history.json"), retention: .forever).entries == history.entries)
    }
}

@Suite struct ParityHistoryLoadRecoveryTests {
    @Test func retryMergesLegacyNotesWithUnsavedNewNotes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-load-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "history.json")
        let legacy = DictationEntry(text: "Legacy kept note", origin: .typed, isKept: true)
        try JSONEncoder().encode([legacy]).write(to: url)
        let blocker = url.deletingPathExtension().appendingPathExtension("notes")
        try Data().write(to: blocker)
        var history = DictationHistory(url: url, retention: .forever)
        let new = DictationEntry(text: "New unsaved note", origin: .typed, isKept: true)
        history.upsert(new)
        #expect(history.saveFailure != nil)
        try FileManager.default.removeItem(at: blocker)
        history.retrySave()
        #expect(history.saveFailure == nil)
        #expect(history.entries.map(\.id) == [new.id, legacy.id])
        #expect(DictationHistory(url: url, retention: .forever).entries == history.entries)
    }
    @Test(arguments: [false, true]) func aClearDuringFailedLoadingDoesNotDeleteNewerNotesOrResurrectHistory(includePinned: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-clear-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "history.json")
        let kept = DictationEntry(text: "Kept", origin: .typed, isKept: true)
        let untouched = DictationEntry(text: "Untouched")
        try JSONEncoder().encode([kept, untouched]).write(to: url)
        let blocker = url.deletingPathExtension().appendingPathExtension("notes")
        try Data().write(to: blocker)
        var history = DictationHistory(url: url, retention: .forever)
        history.clear(includePinned: includePinned)
        let new = DictationEntry(text: "Created after Clear", origin: .typed, isKept: true)
        history.upsert(new)
        try FileManager.default.removeItem(at: blocker)
        history.retrySave()
        #expect(history.entries.map(\.id) == (includePinned ? [new.id] : [new.id, kept.id]))
        #expect(Set(history.deleted.map(\.id)) == Set(includePinned ? [kept.id, untouched.id] : [untouched.id]))
        #expect(DictationHistory(url: url, retention: .forever).entries == history.entries)
    }
}
