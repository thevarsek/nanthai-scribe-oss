import Foundation
import Testing
@testable import ScribeMacCore

@Suite struct DictationHistoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func elapsedTimeBoundariesPreserveOrderAndIdentity() {
        let ages: [TimeInterval] = [0, 86_400, 86_401, 30 * 86_400, 30 * 86_400 + 1]
        let entries = ages.map { DictationEntry(date: now.addingTimeInterval(-$0), text: "fixture") }
        #expect(HistoryRetention.oneDay.prune(entries, now: now) == Array(entries.prefix(2)))
        #expect(HistoryRetention.thirtyDays.prune(entries, now: now) == Array(entries.prefix(4)))
        #expect(HistoryRetention.forever.prune(entries, now: now) == entries)
        #expect(HistoryRetention.off.prune(entries, now: now).isEmpty)
    }

    @Test func launchPrunesAndPersistsExpiredEntries() throws {
        try withHistory { url in
            var history = DictationHistory(url: url, retention: .forever, now: now)
            history.insert("old", retention: .forever, now: now.addingTimeInterval(-86_401))
            history.insert("recent", retention: .forever, now: now)
            let reopened = DictationHistory(url: url, retention: .oneDay, now: now)
            #expect(reopened.entries.map(\.text) == ["recent"])
            #expect(DictationHistory(url: url, retention: .forever, now: now).entries == reopened.entries)
        }
    }

    @Test func eachInsertPrunesUsingItsTime() throws {
        try withHistory { url in
            var history = DictationHistory(url: url, retention: .oneDay, now: now)
            history.insert("first", retention: .oneDay, now: now)
            history.insert("second", retention: .oneDay, now: now.addingTimeInterval(86_401))
            #expect(history.entries.map(\.text) == ["second"])
            #expect(DictationHistory(url: url, retention: .forever).entries == history.entries)
        }
    }

    @Test func offAtLaunchRemovesSavedHistoryAndNeverRecordsNewText() throws {
        try withHistory { url in
            var history = DictationHistory(url: url, retention: .forever, now: now)
            history.insert("old", retention: .forever, now: now)
            history = DictationHistory(url: url, retention: .off, now: now)
            history.insert("must not be saved", retention: .off, now: now)
            #expect(history.entries.isEmpty)
            #expect(DictationHistory(url: url, retention: .forever).entries.isEmpty)
            let saved = try String(contentsOf: url, encoding: .utf8)
            #expect(saved == "[]")
        }
    }

    @Test func changingPolicyAndClearingArePersisted() throws {
        try withHistory { url in
            var history = DictationHistory(url: url, retention: .forever, now: now)
            history.insert("old", retention: .forever, now: now.addingTimeInterval(-31 * 86_400))
            history.insert("recent", retention: .forever, now: now)
            history.prune(retention: .thirtyDays, now: now)
            #expect(history.entries.map(\.text) == ["recent"])
            history.clear()
            #expect(DictationHistory(url: url, retention: .forever).entries.isEmpty)
        }
    }

    @Test func foreverHasNoImplicitCountOrAgeLimit() throws {
        try withHistory { url in
            var history = DictationHistory(url: url, retention: .forever, now: now)
            for number in 0..<60 { history.insert("\(number)", retention: .forever, now: now) }
            #expect(DictationHistory(url: url, retention: .forever,
                                     now: now.addingTimeInterval(365 * 86_400)).entries.count == 60)
        }
    }

    @Test func missingOrInvalidFileStartsEmpty() throws {
        try withHistory { url in
            #expect(DictationHistory(url: url, retention: .forever).entries.isEmpty)
            try Data("invalid".utf8).write(to: url)
            #expect(DictationHistory(url: url, retention: .forever).entries.isEmpty)
        }
    }

    @Test func offKeepsUnreadableHistoryAvailableForIndividualDeletion() throws {
        try withHistory { url in
            try Data("damaged history fixture".utf8).write(to: url)
            let history = DictationHistory(url: url, retention: .off)
            #expect(history.entries.isEmpty)
            #expect(history.unreadable.count == 1)
            let saved = try String(contentsOf: url, encoding: .utf8)
            #expect(saved == "[]")
        }
    }

    @Test func existingJSONKeepsIDsDatesAndText() throws {
        try withHistory { url in
            let entry = DictationEntry(date: now, text: "existing fixture")
            try JSONEncoder().encode([entry]).write(to: url)
            #expect(DictationHistory(url: url, retention: .forever).entries == [entry])
        }
    }

    @Test func clearActionsHaveExplicitScopesAndPersist() throws {
        try withHistory { url in
            var history = DictationHistory(url: url, retention: .forever)
            history.insert("Unedited dictation", retention: .forever)
            let pinned = DictationEntry(text: "Pinned", pinned: true)
            var edited = DictationEntry(text: "Original")
            edited.save("Edited")
            let note = DictationEntry(text: "Written note", origin: .typed)
            for entry in [pinned, edited, note] { history.upsert(entry) }
            history.clear()
            #expect(Set(history.entries.map(\.id)) == Set([pinned.id, edited.id, note.id]))
            #expect(DictationHistory(url: url, retention: .forever).entries == history.entries)
            history.clear(includePinned: true)
            #expect(DictationHistory(url: url, retention: .forever).entries.isEmpty)
        }
    }

    private func withHistory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScribeM2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appending(path: "history.json"))
    }
}

@Suite struct NoteHistoryMigrationTests {
    @Test func legacyMacHistoryMigratesUnderEveryPolicyAndKeepsExplicitNotes() throws {
        let now = Date.now
        let root = FileManager.default.temporaryDirectory.appending(path: "M16MacMigration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), recentID = UUID()
        for retention in HistoryRetention.allCases {
            let url = root.appending(path: retention.rawValue + ".json")
            let legacy: [[String: Any]] = [
                ["id": recentID.uuidString, "date": now.timeIntervalSinceReferenceDate, "text": "Recent"],
                ["id": oldID.uuidString, "date": now.addingTimeInterval(-40 * 86_400).timeIntervalSinceReferenceDate, "text": "Old"]]
            try JSONSerialization.data(withJSONObject: legacy).write(to: url)
            var history = DictationHistory(url: url, retention: retention, now: now)
            let expected = retention == .off ? [] : retention == .forever ? [recentID, oldID] : [recentID]
            #expect(history.entries.map(\.id) == expected)
            let kept = DictationEntry(date: now.addingTimeInterval(-80 * 86_400), text: "Kept").copy(now: now.addingTimeInterval(-40 * 86_400))
            history.upsert(kept)
            history.prune(retention: retention, now: now)
            let reopened = DictationHistory(url: url, retention: retention, now: now)
            #expect(reopened.entries.first?.id == kept.id)
            #expect(reopened.entries.first?.sourceID == kept.sourceID)
            #expect(reopened.entries.map(\.id) == [kept.id] + expected)
            history.clear()
            #expect(history.entries.map(\.id) == [kept.id])
        }
    }
}
