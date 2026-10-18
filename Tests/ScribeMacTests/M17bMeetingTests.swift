import AVFoundation
import Foundation
import ScribeCore
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized)
struct M17bMeetingTests {
    @Test func pauseClosesFilesAndResumeExcludesPausedTime() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "m17b-\(UUID().uuidString)")
        let clip = try MeetingFixtures.clip("Samantha", "The prototype is ready for review.")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: clip) }
        let source = FixtureSource(clips: [clip])
        let session = MeetingCaptureSession(folder: folder, sources: [(MeetingAudioSegment.microphone, source)])
        try await session.start()
        await session.pause()
        #expect(session.paused && source.starts == 1)
        let frozen = session.elapsed
        try await Task.sleep(for: .milliseconds(250))
        #expect(session.elapsed == frozen)
        await session.restart(MeetingAudioSegment.microphone)
        #expect(source.starts == 1)
        await session.resume()
        #expect(!session.paused && source.starts == 2)
        #expect(session.elapsed - frozen < 0.2)
        #expect(session.segments.count == 2)
        #expect(session.segments[1].offset - frozen < 0.2)
        let errors = await session.stop()
        #expect(errors.isEmpty)
        #expect(session.segments.allSatisfy { MeetingAudioFiles.hasAudio(folder.appending(path: $0.file)) })
        // A resumed take retains both closed PCM files, ready for crash recovery.
        let meeting = Meeting(title: "Paused", state: .recording, audio: session.segments)
        let store = MeetingStore(root: folder.appending(path: "store"))
        try await store.save(meeting)
        #expect(try await store.load().first?.audio == session.segments)
    }

    @Test func meterDistinguishesInPersonSilenceFromMissingAudio() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "m17b-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = MeterSource()
        let session = MeetingCaptureSession(folder: folder, sources: [(MeetingAudioSegment.system, source)])
        try await session.start()
        source.frames = 100
        #expect(await session.sourceHealth(MeetingAudioSegment.system) == .none)
        source.frames = 200; source.level = 0.15
        #expect(await session.sourceHealth(MeetingAudioSegment.system) == .level(0.15))
        #expect(await session.sourceHealth(MeetingAudioSegment.system) == .level(0.15))
        try await Task.sleep(for: .milliseconds(550))
        #expect(await session.sourceHealth(MeetingAudioSegment.system) == .warning("Not coming through"))
        await session.pause()
        #expect(await session.sourceHealth(MeetingAudioSegment.system) == .paused)
        _ = await session.stop()
        await session.resume()
        #expect(source.starts == 1)
    }

    @Test func callAudioRemembersSpeechWhileTheRecordingPaneWasClosed() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "m17b-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = MeterSource()
        let session = MeetingCaptureSession(folder: folder, sources: [(MeetingAudioSegment.system, source)])
        try await session.start()
        source.frames = 1000; source.receivedSignal = true; source.level = 0
        #expect(await session.sourceHealth(MeetingAudioSegment.system) == .level(0))
        _ = await session.stop()
    }

    @Test func aMicrophoneFailureDoesNotMarkFlowingCallAudioAsFailed() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "m17b-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let mic = MeterSource(), call = MeterSource()
        mic.failAfterStarts = 1
        let session = MeetingCaptureSession(folder: folder,
            sources: [(MeetingAudioSegment.system, call), (MeetingAudioSegment.microphone, mic)])
        try await session.start()
        await session.restart(MeetingAudioSegment.microphone)
        call.frames = 100; call.level = 0.1
        #expect(session.health != .healthy)
        #expect(await session.sourceHealth(MeetingAudioSegment.microphone) == .warning("Not coming through"))
        #expect(await session.sourceHealth(MeetingAudioSegment.system) == .level(0.1))
        _ = await session.stop()
    }

    @Test func failedStartKeepsAudioAlreadyCapturedByTheOtherSource() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "m17b-\(UUID().uuidString)")
        let domain = "m17b-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let clip = try MeetingFixtures.clip("Samantha", "We should keep the recording.")
        defer {
            try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: clip)
            defaults.removePersistentDomain(forName: domain)
        }
        let recorder = MeetingRecorder(root: folder, defaults: defaults)
        recorder.requestMicrophoneAccess = { true }
        let failing = MeterSource(); failing.failAfterStarts = 0
        recorder.makeSources = { [(MeetingAudioSegment.system, FixtureSource(clips: [clip])), (MeetingAudioSegment.microphone, failing)] }
        await recorder.start(options: .init(languages: [], diarizer: folder.appending(path: "no-model"), summarize: false))
        #expect(!recorder.isRecording && recorder.error != nil)
        let saved = try #require(try await MeetingStore(root: folder).load().first)
        #expect(saved.needsRecovery && saved.audio.count == 1)
        #expect(saved.canRetryTranscription)
        #expect(MeetingAudioFiles.hasAudio(folder.appending(path: saved.id.uuidString).appending(path: saved.audio[0].file)))
    }

    @Test func notesDebounceAndFlushOnQuitWithoutLosingTitle() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "m17b-\(UUID().uuidString)")
        let domain = "m17b-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { try? FileManager.default.removeItem(at: folder); defaults.removePersistentDomain(forName: domain) }
        let recorder = MeetingRecorder(root: folder, defaults: defaults)
        let meeting = Meeting(title: "Original")
        recorder.meetings = [meeting]
        recorder.updateNotes(meeting.id, "Draft")
        recorder.updateNotes(meeting.id, "日本語\nالعربية")
        let store = MeetingStore(root: folder)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await store.load().isEmpty)
        try await Task.sleep(for: .milliseconds(650))
        #expect(try await store.load().first?.notes == "日本語\nالعربية")
        recorder.updateTitle(meeting.id, "Renamed")
        recorder.updateNotes(meeting.id, "Final notes")
        await recorder.finishBeforeQuit()
        let saved = try #require(try await store.load().first)
        #expect(saved.title == "Renamed" && saved.notes == "Final notes")
        #expect(recorder.searchText(for: saved).contains("Final notes"))
    }

    @Test func pauseStateAndAudioSurviveQuit() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "m17b-\(UUID().uuidString)")
        let domain = "m17b-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let clip = try MeetingFixtures.clip("Samantha", "Please send the review notes.")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: clip)
            defaults.removePersistentDomain(forName: domain)
        }
        let recorder = MeetingRecorder(root: folder, defaults: defaults)
        recorder.requestMicrophoneAccess = { true }
        let source = FixtureSource(clips: [clip])
        recorder.makeSources = { [(MeetingAudioSegment.microphone, source)] }
        await recorder.start(options: .init(languages: [], diarizer: folder.appending(path: "no-model"), summarize: false))
        let id = try #require(recorder.recordingID)
        await recorder.togglePause()
        #expect(recorder.paused && recorder.isRecording)
        let frozen = recorder.elapsed
        try await Task.sleep(for: .milliseconds(100))
        await recorder.finishBeforeQuit()
        #expect(!recorder.paused && !recorder.isRecording && recorder.processing.isEmpty)
        let saved = try #require(try await MeetingStore(root: folder).load().first)
        #expect(saved.state == .processing && saved.needsRecovery)
        #expect(saved.duration == frozen)
        #expect(saved.audio.count == 1)
        #expect(MeetingAudioFiles.hasAudio(folder.appending(path: id.uuidString).appending(path: saved.audio[0].file)))
    }

    @Test func writerExposesRMSWithoutChangingAudio() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "m17b-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        for index in 0..<1600 { buffer.floatChannelData?[0][index] = 0.25 }
        let writer = try MeetingAudioWriter(url: url, format: format)
        writer.append(buffer.audioBufferList, hostTime: mach_absolute_time())
        try writer.finish()
        #expect(abs(writer.level - 0.25) < 0.001)
        #expect(writer.frames == 1600)
        #expect(writer.hasSignal)
    }

    @Test func processingStagesSkipOnlyOptionalSpeakers() {
        var progress = MeetingProgress(identifiesSpeakers: false)
        #expect(progress.steps == [.saving, .transcribing, .summarising])
        progress.identifiesSpeakers = true
        #expect(progress.steps == MeetingProgress.Step.allCases)
        progress[.transcribing] = .failed("Could not transcribe")
        #expect(progress[.saving] == .active)
        #expect(progress[.transcribing] == .failed("Could not transcribe"))
        #expect(progress[.summarising] == .pending)
    }
}

@MainActor private final class MeterSource: MeetingAudioSource {
    var frames: Int64 = 0
    var level: Double = 0
    var receivedSignal = false
    var hasSignal: Bool { receivedSignal || level > 0.0001 }
    var firstHostTime: Double? { nil }
    var starts = 0
    var failAfterStarts = Int.max
    func start(url: URL) throws {
        starts += 1
        if starts > failAfterStarts { throw ScribeError.microphoneUnavailable }
    }
    func stop() {}
    func observeInterruptions(_ handler: @escaping @Sendable () -> Void) {}
    func release() {}
}
