import AVFoundation
import Foundation
import Testing
@testable import ScribeCore

@Suite struct ParityReliabilityTests {
    @Test func finishPolicyScalesWithRecordedAudio() {
        #expect(FinishDeadline.seconds(audioLength: 0) == 10)
        #expect(FinishDeadline.seconds(audioLength: 19) == 10)
        #expect(FinishDeadline.seconds(audioLength: 60) == 30)
        #expect(FinishDeadline.seconds(audioLength: 1_800) == 900)
        #expect(FinishDeadline.seconds(audioLength: .nan) == 10)
    }
    @MainActor @Test func realFinalWinsBeforeDeadline() async {
        let result = await FinishDeadline.wait(seconds: 1) { "batch final" } fallback: { "heard" }
        #expect(result == "batch final")
    }
    @MainActor @Test func deadlineDoesNotWaitForUncooperativeWork() async {
        var resume: CheckedContinuation<String, Never>?
        let result = await FinishDeadline.wait(seconds: 0.01) {
            await withCheckedContinuation { resume = $0 }
        } fallback: { "heard" }
        #expect(result == "heard")
        resume?.resume(returning: "late final")
        await Task.yield()
    }
    @Test func speechEnergyKeepsBatchOnlyTakesAlive() {
        let start = Date(timeIntervalSince1970: 1_000)
        var detector = SpeechDetector()
        #expect(!detector.isInactive(startedAt: nil, now: start))
        #expect(detector.isInactive(startedAt: start, now: start.addingTimeInterval(600)))
        detector.observe(level: 0.5, at: start.addingTimeInterval(599))
        #expect(!detector.isInactive(startedAt: start, now: start.addingTimeInterval(1_198)))
        detector.observe(level: 0.01, at: start.addingTimeInterval(1_198))
        #expect(detector.isInactive(startedAt: start, now: start.addingTimeInterval(1_199)))
    }
    @Test func perNoteLoadingKeepsHealthyFilesAndDamageUntilDelete() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(root: root)
        let note = Note(text: "Synthetic fixture", origin: .typed)
        try store.save([note])
        let bad = UUID()
        try Data("corrupt".utf8).write(to: store.file(bad))
        let loaded = try store.load()
        #expect(loaded.notes == [note])
        #expect(loaded.unreadable.map(\.id) == [bad])
        try store.save([note])
        #expect(try Data(contentsOf: store.file(bad)) == Data("corrupt".utf8))
        try store.delete(bad)
        #expect(try store.load().unreadable.isEmpty)
    }
    @Test func perMeetingLoadingKeepsHealthyFilesAndDamageUntilDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let meeting = Meeting(title: "Synthetic fixture")
        try await store.save(meeting)
        let bad = UUID(), folder = store.directory(bad)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: folder.appending(path: "meeting.json"))
        #expect(try await store.load() == [meeting])
        #expect(await store.unreadable.map(\.id) == [bad])
        try await store.delete(bad)
        #expect(try await store.load() == [meeting])
        #expect(await store.unreadable.isEmpty)
    }
    @Test func retryStateRetainsReviewedWordsAndSurvivesRelaunch() throws {
        var meeting = Meeting(title: "Fixture", turns: [.init(speakerID: "you", start: 1, end: 2, text: "Corrected", isEdited: true)],
            audio: [.init(stream: "you", file: "microphone.caf", offset: 0)])
        meeting.processingError = "Synthetic failure"
        #expect(meeting.canRetryTranscription)
        let began = meeting.beginRetry()
        let beganTwice = meeting.beginRetry()
        #expect(began)
        #expect(!beganTwice)
        meeting = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(meeting))
        #expect(meeting.transcriptionRetryPending)
        meeting.replaceTranscript([.init(speakerID: "room-1", start: 1.02, end: 2.02, text: "Recognized")])
        #expect(meeting.turns.first?.text == "Corrected")
        #expect(meeting.turns.first?.isEdited == true)
        #expect(!meeting.transcriptionRetryPending)
        #expect(meeting.summaryNeedsUpdate)
    }
    @Test func failedMeetingStartCanBeRetriedWithoutRelaunch() {
        var meeting = Meeting(title: "Interrupted start", state: .processing,
            audio: [.init(stream: "system", file: "system.caf", offset: 0)])
        meeting.processingError = "The microphone couldn't be started."
        #expect(meeting.canRetryTranscription)
        let began = meeting.beginRetry()
        #expect(began)
        #expect(meeting.transcriptionRetryPending)
        #expect(!meeting.canRetryTranscription)
    }
    @Test func emptyRetryKeepsReviewedTranscriptAndRetryIntent() {
        var meeting = Meeting(title: "Fixture", turns: [.init(speakerID: "you", start: 1, end: 2, text: "Reviewed", isEdited: true)],
            audio: [.init(stream: "you", file: "microphone.caf", offset: 0)])
        meeting.processingError = "Synthetic failure"
        let began = meeting.beginRetry()
        #expect(began)
        meeting.replaceTranscript([])
        #expect(meeting.turns.first?.text == "Reviewed")
        #expect(meeting.transcriptionRetryPending)
    }
    @Test func changedBoundariesDoNotApplyEditsToUnrelatedTurns() {
        var meeting = Meeting(title: "Fixture", turns: [.init(speakerID: "you", start: 1, end: 2, text: "Edit", isEdited: true)])
        meeting.replaceTranscript([.init(speakerID: "you", start: 10, end: 20, text: "New turn")])
        #expect(meeting.turns.first?.text == "New turn")
        #expect(meeting.turns.first?.isEdited == false)
    }
    @Test func failedVoiceEditNeverInsertsAndErrorsNeverExposeInternals() {
        let error = RewriteError.unavailable("Metal MLX ratio=8.2 Tools/README.md")
        #expect(!DictationFailure.shouldInsert(editing: true, rewriteFailed: true))
        #expect(DictationFailure.shouldInsert(editing: false, rewriteFailed: true))
        #expect(DictationFailure.shouldInsert(editing: true, rewriteFailed: false))
        #expect(DictationFailure.rewrite(error, editing: false) == "Refine didn't finish. Your words were inserted as spoken.")
        #expect(DictationFailure.rewrite(error, editing: true) == "Couldn't edit. Your text is unchanged.")
        #expect(!DictationFailure.microphoneDenied(onPhone: true).contains("System Settings"))
    }
    @Test func lastDictationExpiresAtOneHour() {
        let start = Date(timeIntervalSince1970: 1_000)
        let last = LastDictationRecovery(text: "Fixture", createdAt: start)
        #expect(!last.isExpired(at: start.addingTimeInterval(3_599)))
        #expect(last.isExpired(at: start.addingTimeInterval(3_600)))
    }
}

@MainActor @Suite struct ParityVocabularyRecoveryTests {
    @Test func retryOfAnUnreadableVocabularyNeverOverwritesTheFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-unreadable-vocabulary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "vocabulary.json")
        let corrupt = Data("unreadable vocabulary".utf8)
        try corrupt.write(to: file)
        let vocabulary = Vocabulary(directory: root)
        let failure = vocabulary.saveFailure?.id
        vocabulary.retrySave()
        #expect(try Data(contentsOf: file) == corrupt)
        #expect(vocabulary.saveFailure?.id == failure)
        let repaired = Vocabulary.Document(dictionary: [DictionaryEntry(term: "Restored term")])
        try JSONEncoder().encode(repaired).write(to: file, options: .atomic)
        vocabulary.retrySave()
        #expect(vocabulary.dictionary == repaired.dictionary)
        #expect(vocabulary.persistenceError == nil)
        #expect(vocabulary.saveFailure == nil)
    }
    @Test func failedVocabularySaveRetainsEditsAndOnlyOneFailureUntilSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-vocabulary-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vocabulary = Vocabulary(directory: root)
        try FileManager.default.removeItem(at: vocabulary.fileURL)
        try FileManager.default.createDirectory(at: vocabulary.fileURL, withIntermediateDirectories: true)
        vocabulary.dictionary = [DictionaryEntry(term: "Synthetic term")]
        let first = vocabulary.saveFailure?.id
        #expect(first != nil)
        vocabulary.snippets = [Snippet(trigger: "Synthetic trigger", text: "Synthetic text")]
        #expect(vocabulary.saveFailure?.id == first)
        #expect(vocabulary.dictionary.first?.term == "Synthetic term")
        #expect(vocabulary.snippets.first?.text == "Synthetic text")
        try FileManager.default.removeItem(at: vocabulary.fileURL)
        vocabulary.retrySave()
        #expect(vocabulary.saveFailure == nil)
        let reopened = Vocabulary(directory: root)
        #expect(reopened.dictionary == vocabulary.dictionary)
        #expect(reopened.snippets == vocabulary.snippets)
    }
}

@MainActor @Suite struct ParityLiveFinishTests {
    @Test func batchFinalAfterFiveSecondsIsDeliveredAndAudioWaitsForAcknowledgement() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-batch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let transcriber = LiveTranscriber(recoveryRoot: root)
        let engine = DelayedBatch(text: "Synthetic batch result", delay: .seconds(6))
        let (format, sink) = try await transcriber.start(locales: engine.languages, batchEngines: [engine])
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        buffer.floatChannelData?[0].initialize(repeating: 0.1, count: 1_600)
        sink.yield(.init(buffer: buffer))
        let result = await transcriber.finish(keepingAudioUntilDelivery: true)
        #expect(result.text == "Synthetic batch result")
        #expect(RetainedDictation.load(root: root).count == 1)
        transcriber.discardRetainedTake()
        #expect(RetainedDictation.load(root: root).isEmpty)
    }
    @Test func emptyBatchKeepsRecordingForRetryAcrossOwnerRecreation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-empty-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let transcriber = LiveTranscriber(recoveryRoot: root)
        let engine = DelayedBatch(text: "", delay: .zero)
        let (format, sink) = try await transcriber.start(locales: engine.languages, batchEngines: [engine])
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        buffer.floatChannelData?[0].initialize(repeating: 0.1, count: 1_600)
        sink.yield(.init(buffer: buffer))
        #expect(await transcriber.finish(keepingAudioUntilDelivery: true).text.isEmpty)
        #expect(RetainedDictation.load(root: root).count == 1)
        let moved = root.appendingPathExtension("moved")
        defer { try? FileManager.default.removeItem(at: moved) }
        try FileManager.default.moveItem(at: root, to: moved)
        let recovered = try #require(RetainedDictation.load(root: moved).first)
        #expect(recovered.file.resolvingSymlinksInPath().path.hasPrefix(moved.resolvingSymlinksInPath().path))
        #expect(MeetingAudioFiles.hasAudio(recovered.file))
    }
}
private struct DelayedBatch: BatchTranscriber {
    let id = "par1-test-batch"
    let languages = [Locale(identifier: "zz-ZZ")]
    let text: String
    let delay: Duration
    func isAvailable() async -> Bool { true }
    func transcribe(samples: [Float], sampleRate: Double) async throws -> BatchTranscript {
        try await Task.sleep(for: delay)
        return .init(text: text, confidence: 1)
    }
}
