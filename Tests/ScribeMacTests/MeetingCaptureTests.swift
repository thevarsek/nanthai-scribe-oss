import AppKit
import AVFoundation
import Foundation
import ScribeCore
import Speech
import Testing
@testable import ScribeMac

/// TTS clips stand in for people; the recorder's own writer stands in for the microphone.
enum MeetingFixtures {
    static var diarizer: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "NanthAi Scribe/Models/" + ModelCatalog.meetingDiarizer.id, directoryHint: .isDirectory)
    }
    static var diarizerInstalled: Bool { ModelStore.isInstalled(ModelCatalog.meetingDiarizer, at: diarizer) }
    /// Speech assets are reserved per app: the test host must claim the already-installed ones, as the app does at launch.
    static func installed(_ identifiers: String...) async -> Bool {
        let installed = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
        guard identifiers.allSatisfy({ installed.contains($0) }) else { return false }
        try? await LiveTranscriber.prepareAssets(locales: identifiers.map(Locale.init(identifier:)))
        return true
    }
    static func clip(_ voice: String, _ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "scribe-m17a-\(UUID().uuidString).aiff")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/say")
        process.arguments = ["-v", voice, "-o", url.path, text]
        try process.run()
        process.waitUntilExit()
        return url
    }
    /// Plays clips into a writer the way a tap would. The writer is returned unfinished: a
    /// crashed process never closes its file either.
    @discardableResult
    static func write(_ clips: [URL], to url: URL) async throws -> MeetingAudioWriter {
        let files = try clips.map { try AVAudioFile(forReading: $0) }
        let format = try #require(files.first?.processingFormat)
        let writer = try MeetingAudioWriter(url: url, format: format)
        var expected = 0.0
        for file in files {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            expected += Double(buffer.frameLength) * MeetingAudioWriter.sampleRate / format.sampleRate
            writer.append(buffer.audioBufferList, hostTime: mach_absolute_time())
        }
        while Double(writer.frames) < expected - 64 { try await Task.sleep(for: .milliseconds(20)) }
        return writer
    }
}

/// A microphone that "hears" fixture clips on every start, or refuses to come back after a restart.
@MainActor final class FixtureSource: MeetingAudioSource {
    var clips: [URL]
    var failRestart = false
    var starts = 0
    var writer: MeetingAudioWriter?
    var forcedFrames: Int64?
    init(clips: [URL] = []) { self.clips = clips }
    func start(url: URL) async throws {
        starts += 1
        if failRestart, starts > 1 { throw ScribeError.microphoneUnavailable }
        writer = clips.isEmpty ? nil : try await MeetingFixtures.write(clips, to: url)
    }
    func stop() throws { try writer?.finish() }
    var frames: Int64 { forcedFrames ?? writer?.frames ?? 0 }
    var firstHostTime: Double? { writer?.firstHostTime }
    func observeInterruptions(_ handler: @escaping @Sendable () -> Void) {}
    func release() {}
}

@MainActor
@Suite(.serialized)
struct MeetingCaptureTests {
    private func makeRecorder(root: URL, keepAudio: Bool = false) throws -> (MeetingRecorder, UserDefaults, String) {
        let domain = "ScribeM17a-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defaults.set(keepAudio, forKey: "meetingKeepAudio")
        let recorder = MeetingRecorder(root: root, defaults: defaults)
        recorder.requestMicrophoneAccess = { true }
        return (recorder, defaults, domain)
    }
    private func options(_ languages: [String]) -> MeetingProcessingOptions {
        .init(languages: languages.map(Locale.init(identifier:)), diarizer: MeetingFixtures.diarizer, summarize: false)
    }
    private func awaitProcessing(_ recorder: MeetingRecorder, seconds: Int = 120) async throws {
        for _ in 0..<(seconds * 10) where !recorder.processing.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(recorder.processing.isEmpty)
    }

    @Test func writerCopiesBorrowedSamplesAndFlushesBeforeClose() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let writer = try MeetingAudioWriter(url: url, format: format)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<1600 { samples[index] = 0.25 }
        writer.append(buffer.audioBufferList, hostTime: mach_absolute_time())
        for index in 0..<1600 { samples[index] = 0 }
        try writer.finish()
        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 1600)
        #expect(file.fileFormat.commonFormat == .pcmFormatInt16)
        try file.read(into: buffer)
        #expect(abs((buffer.floatChannelData?[0][100] ?? 0) - 0.25) < 0.001)
        #expect(writer.frames == 1600)
        #expect(writer.firstHostTime != nil)
    }

    @Test func writerResamplesToSixteenKilohertzMono() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let writer = try MeetingAudioWriter(url: url, format: format)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for index in 0..<48_000 { buffer.floatChannelData?[0][index] = 0.5; buffer.floatChannelData?[1][index] = 0.5 }
        for _ in 0..<4 { writer.append(buffer.audioBufferList, hostTime: mach_absolute_time()) }
        try writer.finish()
        let file = try AVAudioFile(forReading: url)
        #expect(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
        #expect(abs(Double(file.length) - 64_000) < 200)
    }

    @Test func systemWriterSelectsTapAfterHardwareInputs() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let mono = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let stereo = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 64))
        buffer.frameLength = 64
        for index in 0..<64 { buffer.floatChannelData?[0][index] = 0.1; buffer.floatChannelData?[1][index] = 0.8 }
        let writer = try MeetingAudioWriter(url: url, format: mono)
        writer.append(buffer.audioBufferList, hostTime: mach_absolute_time(), tapOnly: true)
        try writer.finish()
        let file = try AVAudioFile(forReading: url)
        let read = try #require(AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 64))
        try file.read(into: read)
        #expect(abs((read.floatChannelData?[0][20] ?? 0) - 0.8) < 0.001)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIBE_SKIP_SPEECH"] == nil))
    func recoversMeetingAfterKillMidRecording() async throws {
        guard await MeetingFixtures.installed("en_US") else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clip = try MeetingFixtures.clip("Samantha", "The prototype is ready. Let's review accessibility before Friday's launch.")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: clip) }
        let microphone = FixtureSource(clips: [clip])
        let first = try makeRecorder(root: root)
        defer { first.1.removePersistentDomain(forName: first.2) }
        var recorder = first.0
        recorder.makeSources = { [(MeetingAudioSegment.system, FixtureSource()), (MeetingAudioSegment.microphone, microphone)] }
        await recorder.start(options: options(["en_US"]))
        #expect(recorder.error == nil)
        let id = try #require(recorder.recordingID)
        try await Task.sleep(for: .milliseconds(200))
        // Kill: no stop(), the audio file is still open, meeting.json still says "recording".
        let folder = root.appending(path: id.uuidString)
        let onDisk = try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: folder.appending(path: "meeting.json")))
        #expect(onDisk.state == .recording && onDisk.audio.map(\.file).contains("microphone-1.caf"))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "microphone-1.caf").path))
        recorder = try makeRecorder(root: root).0
        await recorder.load()
        #expect(recorder.meetings.first?.needsRecovery == true)
        recorder.recover(options: options(["en_US"]))
        #expect(recorder.processing.contains(id))
        try await awaitProcessing(recorder)
        let recovered = try #require(recorder.meetings.first { $0.id == id })
        #expect(recovered.state == .done && recovered.recovered)
        #expect(recovered.duration > 2)
        #expect(recovered.endedAt != nil)
        #expect(recovered.processingError == nil)
        #expect(MeetingExport.transcript(recovered).localizedCaseInsensitiveContains("prototype"))
        #expect(recovered.audio.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "microphone-1.caf").path))
        _ = microphone
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIBE_SKIP_SPEECH"] == nil))
    func quitFlushesAudioAndLeavesProcessingForNextLaunch() async throws {
        guard await MeetingFixtures.installed("en_US") else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clip = try MeetingFixtures.clip("Samantha", "Please send the final report before Friday.")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: clip) }
        let (recorder, defaults, domain) = try makeRecorder(root: root, keepAudio: true)
        defer { defaults.removePersistentDomain(forName: domain) }
        recorder.makeSources = { [(MeetingAudioSegment.system, FixtureSource()), (MeetingAudioSegment.microphone, FixtureSource(clips: [clip]))] }
        await recorder.start(options: options(["en_US"]))
        let id = try #require(recorder.recordingID)
        let clock = ContinuousClock.now
        await recorder.finishBeforeQuit()
        #expect(clock.duration(to: .now) < .seconds(3))
        #expect(recorder.processing.isEmpty)
        let folder = root.appending(path: id.uuidString)
        let onDisk = try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: folder.appending(path: "meeting.json")))
        #expect(onDisk.state == .processing)
        #expect(MeetingAudioFiles.hasAudio(folder.appending(path: "microphone-1.caf")))
        let next = try makeRecorder(root: root, keepAudio: true).0
        await next.load()
        next.recover(options: options(["en_US"]))
        try await awaitProcessing(next)
        let recovered = try #require(next.meetings.first { $0.id == id })
        #expect(recovered.state == .done && !recovered.turns.isEmpty)
        #expect(recovered.audio.map(\.file) == ["microphone-1.m4a"])
        #expect(MeetingAudioFiles.hasAudio(folder.appending(path: "microphone-1.m4a")))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "microphone-1.caf").path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIBE_SKIP_SPEECH"] == nil))
    func inPersonMeetingSeparatesVoicesWithoutSystemAudio() async throws {
        guard await MeetingFixtures.installed("en_US") else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clips = [
            try MeetingFixtures.clip("Samantha", "The prototype is ready, so let's review accessibility before the launch on Friday."),
            try MeetingFixtures.clip("Daniel", "I will arrange the review for Thursday and invite the support team to join us."),
            try MeetingFixtures.clip("Samantha", "Thank you. The budget stays the same for this quarter."),
            try MeetingFixtures.clip("Daniel", "Agreed. I will send the release notes after the review."),
        ]
        defer { try? FileManager.default.removeItem(at: root); clips.forEach { try? FileManager.default.removeItem(at: $0) } }
        let (recorder, defaults, domain) = try makeRecorder(root: root)
        defer { defaults.removePersistentDomain(forName: domain) }
        recorder.makeSources = { [(MeetingAudioSegment.system, FixtureSource()), (MeetingAudioSegment.microphone, FixtureSource(clips: clips))] }
        await recorder.start(options: options(["en_US"]))
        let id = try #require(recorder.recordingID)
        await recorder.stop()
        try await awaitProcessing(recorder)
        let meeting = try #require(recorder.meetings.first { $0.id == id })
        #expect(meeting.processingError == nil)
        #expect(!meeting.turns.isEmpty)
        if MeetingFixtures.diarizerInstalled {
            let room = meeting.speakers.filter { $0.id.hasPrefix("room-") }
            #expect(room.count > 1, "speakers: \(meeting.speakers.map(\.name))")
            #expect(!meeting.speakers.contains { $0.id == "you" })
        } else {
            #expect(meeting.speakers.map(\.id) == ["you"])
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIBE_SKIP_SPEECH"] == nil))
    func languageIsDetectedAmongDictationLanguages() async throws {
        guard await MeetingFixtures.installed("en_US", "it_IT") else { return }
        let italian = try MeetingFixtures.clip("Alice", "Domani mattina prendiamo il treno per Milano. Ricordati di portare i biglietti e i documenti per la riunione.")
        let english = try MeetingFixtures.clip("Samantha", "Please send the final report before Friday. The meeting starts at nine tomorrow morning.")
        defer { try? FileManager.default.removeItem(at: italian); try? FileManager.default.removeItem(at: english) }
        let languages = [Locale(identifier: "en_US"), Locale(identifier: "it_IT")]
        #expect(await MeetingLanguage.detect(files: [italian], among: languages, parakeet: nil).identifier == "it_IT")
        #expect(await MeetingLanguage.detect(files: [english], among: languages, parakeet: nil).identifier == "en_US")
        #expect(await MeetingLanguage.detect(files: [italian], among: [languages[0]], parakeet: nil).identifier == "en_US")
    }

    @Test func parakeetServesOnlyPackLanguages() async {
        for locale in await ParakeetTranscriber.appleUnsupportedLanguages.prefix(2) {
            #expect(await MeetingTranscriber.needsParakeet(locale))
        }
        #expect(await !MeetingTranscriber.needsParakeet(Locale(identifier: "en_US")))
        #expect(await !MeetingTranscriber.needsParakeet(Locale(identifier: "zz_ZZ")))
    }

    @Test func interruptionOpensNewSegmentAndKeepsOffsets() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clip = try MeetingFixtures.clip("Samantha", "Hello")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: clip) }
        let microphone = FixtureSource(clips: [clip])
        let session = MeetingCaptureSession(folder: folder, sources: [(MeetingAudioSegment.system, FixtureSource()), (MeetingAudioSegment.microphone, microphone)])
        var changes = 0
        session.onChange = { changes += 1 }
        try await session.start()
        #expect(session.segments.map(\.file) == ["system-1.caf", "microphone-1.caf"])
        try await Task.sleep(for: .milliseconds(300))
        await session.restart(MeetingAudioSegment.microphone)
        #expect(session.health == .healthy && session.restarts == 1)
        let mic = session.segments.filter { $0.stream == MeetingAudioSegment.microphone }
        #expect(mic.map(\.file) == ["microphone-1.caf", "microphone-2.caf"])
        #expect(mic[1].offset > mic[0].offset)
        #expect(microphone.starts == 2 && changes >= 3)
        let errors = await session.stop()
        #expect(errors.isEmpty)
        // The system stream never received audio: its file is dropped rather than transcribed.
        #expect(session.segments.map(\.file) == ["microphone-1.caf", "microphone-2.caf"])
        #expect(session.segments.allSatisfy { MeetingAudioFiles.hasAudio(folder.appending(path: $0.file)) })
    }

    @Test func stalledMicrophoneRestartsThenFails() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let microphone = FixtureSource()
        microphone.forcedFrames = 0
        let session = MeetingCaptureSession(folder: folder, sources: [(MeetingAudioSegment.microphone, microphone)])
        try await session.start()
        for _ in 0..<MeetingCaptureSession.stallRestartTicks { await session.checkProgress() }
        #expect(microphone.starts == 2 && session.health == .healthy)
        for _ in MeetingCaptureSession.stallRestartTicks..<MeetingCaptureSession.stallFailureTicks { await session.checkProgress() }
        #expect(session.health == .failed(MeetingCaptureError.microphoneStalled.localizedDescription))
        let errors = await session.stop()
        #expect(errors.contains(MeetingCaptureError.microphoneStalled.localizedDescription))
        #expect(errors.contains(MeetingCaptureError.noAudio.localizedDescription))
    }

    @Test func failedRestartStopsClockAndSurfacesHealth() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clip = try MeetingFixtures.clip("Samantha", "Hello")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: clip) }
        let (recorder, defaults, domain) = try makeRecorder(root: root)
        defer { defaults.removePersistentDomain(forName: domain) }
        let microphone = FixtureSource(clips: [clip])
        microphone.failRestart = true
        recorder.makeSources = { [(MeetingAudioSegment.microphone, microphone)] }
        await recorder.start(options: options(["en_US"]))
        let session = try #require(recorder.session)
        #expect(recorder.captureHealth == .healthy)
        await session.restart(MeetingAudioSegment.microphone)
        #expect(session.health != .healthy)
        try await Task.sleep(for: .milliseconds(1300))
        guard case .failed = recorder.captureHealth else { Issue.record("health not surfaced"); return }
        let frozen = recorder.elapsed
        try await Task.sleep(for: .milliseconds(2200))
        #expect(recorder.elapsed == frozen)
        #expect(recorder.isRecording)
        // Stop still keeps what was captured; the transcript step runs on it.
        let id = try #require(recorder.recordingID)
        await recorder.stop()
        try await awaitProcessing(recorder)
        let meeting = try #require(recorder.meetings.first { $0.id == id })
        #expect(meeting.processingError?.contains(ScribeError.microphoneUnavailable.localizedDescription) == true)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: id.uuidString).appending(path: "microphone-1.caf").path))
    }

    @Test func searchTextIsCachedAndTitleSavesAreDebounced() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (recorder, defaults, domain) = try makeRecorder(root: root)
        defer { defaults.removePersistentDomain(forName: domain) }
        let meeting = Meeting(title: "Plan", speakers: [.init(id: "you", name: "You")], turns: [.init(speakerID: "you", start: 0, end: 1, text: "Budget")])
        recorder.meetings = [meeting]
        #expect(recorder.searchText(for: meeting).contains("Budget"))
        for title in ["P", "Pl", "Pla", "Plan B"] { recorder.updateTitle(meeting.id, title) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: meeting.id.uuidString).appending(path: "meeting.json").path))
        try await Task.sleep(for: .milliseconds(700))
        let store = MeetingStore(root: root)
        #expect(try await store.load().first?.title == "Plan B")
        #expect(recorder.searchText(for: recorder.meetings[0]).hasPrefix("Plan B"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M7_LIVE_MIC"] != nil))
    func meetingAndDictationMicrophonesAreIndependent() async throws {
        guard await Microphone.requestAccess() else { throw ScribeError.microphoneDenied }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let meeting = MeetingMicrophone()
        let dictation = Microphone()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let (stream, sink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let consumer = Task { var frames = 0; for await input in stream { frames += Int(input.buffer.frameLength) }; return frames }
        try meeting.start(url: url)
        defer { try? meeting.stop(); dictation.stop(); sink.finish() }
        try dictation.start(format: format, sink: sink, onLevel: { _ in })
        try await Task.sleep(for: .seconds(2))
        dictation.stop(); sink.finish()
        let before = meeting.writer?.frames ?? 0
        let dictationFrames = await consumer.value
        try await Task.sleep(for: .seconds(1))
        try meeting.stop()
        #expect(dictationFrames > 0)
        #expect((meeting.writer?.frames ?? 0) > before)
        print("CONCURRENT MIC: dictation=\(dictationFrames) frames; meeting continued after dictation stopped")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M7_LIVE_TAP"] != nil))
    func processTapCapturesOtherProcess() async throws {
        let folder = URL(filePath: "/tmp/scribe-m7-e2e")
        let capture = MeetingSystemAudio()
        do { try await capture.start(url: folder.appending(path: "live-system.caf")) }
        catch { print("LIVE TAP BLOCKED: \(error.localizedDescription)"); throw error }
        let player = Process()
        player.executableURL = URL(filePath: "/usr/bin/afplay")
        player.arguments = [folder.appending(path: "system.wav").path]
        try player.run()
        defer { if player.isRunning { player.terminate() }; Task { try? await capture.stop() } }
        try await Task.sleep(for: .seconds(10))
        try await capture.stop()
        let frames = await capture.writer?.frames ?? 0
        print("LIVE TAP: \(frames) frames captured in 10 seconds")
        #expect(frames > 0)
        let file = try AVAudioFile(forReading: folder.appending(path: "live-system.caf"))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let values = try #require(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).map { abs(values[$0]) }.max() ?? 0
        print("LIVE TAP: peak amplitude \(peak)")
        #expect(peak > 0.001)
    }
}
