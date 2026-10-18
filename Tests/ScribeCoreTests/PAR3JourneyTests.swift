import Foundation
import Testing
@testable import ScribeCore

@Suite struct PAR3JourneyTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PAR3-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func purgeBoundaryAndUnrelatedItemsSurvive() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(!RecentlyDeleted.isExpired(nil, now: now))
        #expect(!RecentlyDeleted.isExpired(now.addingTimeInterval(-RecentlyDeleted.retention + 1), now: now))
        #expect(RecentlyDeleted.isExpired(now.addingTimeInterval(-RecentlyDeleted.retention), now: now))
        var expired = Note(text: "expired", origin: .typed)
        expired.deletedAt = now.addingTimeInterval(-RecentlyDeleted.retention)
        var fresh = Note(text: "fresh", origin: .typed, pinned: true)
        fresh.deletedAt = now
        let active = Note(text: "active", origin: .typed)
        let notes = NoteStore(root: root.appending(path: "Notes"))
        try notes.save([expired, fresh, active]); try notes.purgeDeleted(now: now)
        #expect(Set(try notes.load().notes.map(\.id)) == Set([fresh.id, active.id]))
        let store = MeetingStore(root: root.appending(path: "Meetings"))
        var meeting = Meeting(title: "deleted", audio: [.init(stream: "system", file: "audio.m4a", offset: 0)])
        meeting.deletedAt = expired.deletedAt
        try await store.save(meeting)
        let file = store.directory(meeting.id).appending(path: "audio.m4a")
        try Data([1, 2, 3]).write(to: file)
        try await store.purgeDeleted(now: now)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try await store.load().isEmpty)
    }
    @Test func legacyMeetingsGetStableModifiedAndNoDeletion() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let meeting = Meeting(title: "legacy", startedAt: date)
        let data = try JSONEncoder().encode(meeting)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "modified")
        let restored = try JSONDecoder().decode(Meeting.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.modified == date)
        #expect(restored.deletedAt == nil)
    }
    @Test func importedRecordingOwnsOnlyACopyAndPreservesMetadata() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Interview.aiff")
        let bytes = Data([0, 1, 2, 3]); try bytes.write(to: source)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: source.path)
        let metadata = try RecordingImport(url: source)
        let store = MeetingStore(root: root.appending(path: "Meetings"))
        let meeting = try await metadata.copy(from: source, into: store, languages: ["en-GB"])
        #expect(meeting.title == "Interview")
        #expect(abs(meeting.startedAt.timeIntervalSince(metadata.createdAt)) < 1)
        #expect(meeting.state == .processing)
        #expect(meeting.languages == ["en-GB"])
        let copy = store.directory(meeting.id).appending(path: try #require(meeting.audio.first?.file))
        #expect(try Data(contentsOf: copy) == bytes)
        try await store.delete(meeting.id)
        #expect(try Data(contentsOf: source) == bytes)
        for ext in RecordingImport.extensions {
            let file = root.appending(path: "sample." + ext.uppercased()); try bytes.write(to: file)
            #expect(try RecordingImport(url: file).fileExtension == ext)
        }
        #expect(throws: (any Error).self) { try RecordingImport(url: root.appending(path: "image.png")) }
    }
    @Test func backupRoundTripIncludesAudioAndLearningButNotDeletedOrSettings() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var note = Note(text: "edited", origin: .typed, isKept: true, pinned: true, original: "original")
        note.modified = Date(timeIntervalSince1970: 1_234)
        var deleted = note.copy(); deleted.deletedAt = .now
        let meeting = Meeting(title: "Review", audio: [.init(stream: "system", file: "kept.m4a", offset: 4)], notes: "Private notes")
        let directory = root.appending(path: meeting.id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audio = Data([4, 5, 6]); try audio.write(to: directory.appending(path: "kept.m4a"))
        var learned = LearningStore.Document()
        let pair = CorrectionPair(heard: "nan thai", meant: "NanthAi")
        _ = learned.corrections.record(pair, at: .now, canAsk: false)
        learned.keyboard.add("NanthAi")
        let backup = LibraryBackup(notes: [note, deleted], meetings: [meeting], dictionary: [.init(term: "NanthAi")],
                                   snippets: [.init(trigger: "signature", text: "Regards")], learning: learned)
        let package = try backup.fileWrapper(meetingRoot: root)
        let url = root.appending(path: "Library.scribebackup")
        try package.write(to: url, options: .atomic, originalContentsURL: nil)
        let read = try FileWrapper(url: url, options: .immediate)
        let restored = try LibraryBackup(fileWrapper: read)
        #expect(restored == backup)
        #expect(restored.notes == [note])
        #expect(restored.learning == learned)
        #expect(read.fileWrappers?["settings.json"] == nil)
        let target = root.appending(path: "Imported")
        try restored.restoreAudio(from: read, local: [], meetingRoot: target)
        #expect(try Data(contentsOf: target.appending(path: meeting.id.uuidString + "/kept.m4a")) == audio)
    }
    @Test func mergeByIdentityUsesNewerAndIsIdempotentWithoutDeletion() {
        let earlier = Date(timeIntervalSince1970: 1_000), later = Date(timeIntervalSince1970: 2_000)
        let original = Note(createdAt: earlier, text: "old", origin: .typed)
        var edited = original; edited.save("new", now: later)
        let onlyLocal = Note(text: "local", origin: .typed)
        var oldMeeting = Meeting(title: "old", startedAt: earlier)
        oldMeeting.modified = earlier
        var newMeeting = oldMeeting; newMeeting.title = "new"; newMeeting.modified = later
        let id = UUID()
        let dictionary = DictionaryEntry(id: id, term: "old", modified: earlier)
        let newerWord = DictionaryEntry(id: id, term: "new", modified: later)
        let snippetID = UUID()
        let local = LibraryBackup(notes: [original, onlyLocal], meetings: [newMeeting], dictionary: [dictionary],
                                  snippets: [.init(id: snippetID, trigger: "old", modified: earlier)], learning: .init())
        let incoming = LibraryBackup(notes: [edited], meetings: [oldMeeting], dictionary: [newerWord],
                                     snippets: [.init(id: snippetID, trigger: "new", modified: later)], learning: .init())
        let merged = local.merging(incoming)
        #expect(merged.notes == [edited, onlyLocal])
        #expect(merged.meetings == [newMeeting])
        #expect(merged.dictionary == [newerWord])
        #expect(merged.snippets.first?.trigger == "new")
        #expect(merged.merging(incoming) == merged)
    }
    @Test func backupRejectsFutureVersionAndUnsafeAudioPaths() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var backup = LibraryBackup(notes: [], meetings: [], dictionary: [], snippets: [], learning: .init())
        backup.version = 2
        let future = try backup.fileWrapper(meetingRoot: root)
        #expect(throws: (any Error).self) { try LibraryBackup(fileWrapper: future) }
        backup.version = 1
        backup.meetings = [Meeting(title: "Bad", audio: [.init(stream: "system", file: "../outside.m4a", offset: 0)])]
        #expect(throws: (any Error).self) { try backup.fileWrapper(meetingRoot: root) }
    }
    @Test func audioRetentionBelongsToTheMeetingAndSurvivesCoding() throws {
        let turn = MeetingTurn(speakerID: "one", start: 0, end: 2, text: "Fixture")
        let audio = MeetingAudioSegment(stream: "system", file: "kept.m4a", offset: 0)
        let kept = Meeting(title: "kept", turns: [turn], audio: [audio], retainsAudio: true)
        let discarded = Meeting(title: "discard", turns: [turn], audio: [audio], retainsAudio: false)
        let legacyKept = Meeting(title: "legacy", turns: [turn], audio: [audio])
        #expect(kept.shouldKeepAudio(fallback: false))
        #expect(!discarded.shouldKeepAudio(fallback: true))
        #expect(legacyKept.shouldKeepAudio(fallback: false))
        var legacyProcessing = legacyKept; legacyProcessing.state = .processing
        #expect(!legacyProcessing.shouldKeepAudio(fallback: false))
        #expect(legacyProcessing.shouldKeepAudio(fallback: true))
        let restored = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(kept))
        #expect(restored.shouldKeepAudio(fallback: false))
    }

    @Test func importedCopyOutlivesASymlinkTarget() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appending(path: "Original.m4a"), link = root.appending(path: "Alias.m4a")
        let bytes = Data([1, 2, 3]); try bytes.write(to: original)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let store = MeetingStore(root: root.appending(path: "Meetings"))
        let meeting = try await RecordingImport(url: link).copy(from: link, into: store, languages: [])
        let copy = store.directory(meeting.id).appending(path: try #require(meeting.audio.first?.file))
        #expect(try copy.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        try FileManager.default.removeItem(at: original)
        #expect(try Data(contentsOf: copy) == bytes)
    }

}
