import AppKit
import AVFoundation
import Observation
import ScribeCore

/// Everything the finish pipeline needs, resolved up front so a recovered meeting can be
/// processed at launch without a recording in progress.
struct MeetingProcessingOptions: Sendable {
    var languages: [Locale]
    var gemma: URL?
    var parakeet: URL?
    var diarizer: URL
    var summarize = true
    init(languages: [Locale], gemma: URL? = nil, parakeet: URL? = nil, diarizer: URL, summarize: Bool = true) {
        self.languages = languages; self.gemma = gemma; self.parakeet = parakeet; self.diarizer = diarizer
        self.summarize = summarize
    }
    @MainActor init(dictation: Dictation) {
        self.init(languages: dictation.languages.map(Locale.init(identifier:)),
                  gemma: dictation.engine == .gemma && dictation.models.isInstalled(ModelCatalog.gemma)
                      ? dictation.models.directory(for: ModelCatalog.gemma) : nil,
                  parakeet: dictation.models.isInstalled(ModelCatalog.parakeet)
                      ? dictation.models.directory(for: ModelCatalog.parakeet) : nil,
                  diarizer: dictation.models.directory(for: ModelCatalog.meetingDiarizer))
    }
}

@MainActor @Observable
final class MeetingRecorder {
    private(set) var unreadableMeetings: [UnreadableItem] = []
    var deletedMeetings: [Meeting] = []
    var meetings: [Meeting] = [] { didSet { searchCache = [:] } }
    var selection: UUID?
    var showConsent = false
    var error: String?
    /// Capture that failed mid-meeting; the recording stays open so Stop still saves what exists.
    private(set) var captureHealth: MeetingCaptureSession.Health = .healthy
    private(set) var starting = false
    private(set) var assetProgress: Double?
    private(set) var recordingID: UUID?
    private(set) var processing: Set<UUID> = []
    var elapsed: Double = 0
    private(set) var paused = false
    private(set) var changingPause = false
    private(set) var progress: [UUID: MeetingProgress] = [:]
    private var notesSaves: [UUID: Task<Void, Never>] = [:]
    let store: MeetingStore
    private let defaults: UserDefaults
    private(set) var session: MeetingCaptureSession?
    private var options: MeetingProcessingOptions?
    private(set) var ticker: Task<Void, Never>?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var saving: Task<Void, Never>?
    private var titleSave: Task<Void, Never>?
    private var pendingTitle: UUID?
    private var summarizing: Set<UUID> = []
    private var quitting = false
    @ObservationIgnored private var searchCache: [UUID: String] = [:]
    /// Replaced by tests with sources that write fixtures or fail on demand.
    @ObservationIgnored var requestMicrophoneAccess: @Sendable () async -> Bool = { await Microphone.requestAccess() }
    @ObservationIgnored var makeSources: @MainActor () -> [(stream: String, source: any MeetingAudioSource)] = {
        [(MeetingAudioSegment.system, MeetingSystemAudio()), (MeetingAudioSegment.microphone, MeetingMicrophone())]
    }
    #if DEBUG
    func previewPreparation(_ progress: Double?) { starting = progress != nil; assetProgress = progress }
    #endif
    var isRecording: Bool { recordingID != nil }
    var showReminder: Bool {
        get { defaults.object(forKey: "meetingShowReminder") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "meetingShowReminder") }
    }
    var keepAudio: Bool { defaults.bool(forKey: "meetingKeepAudio") }

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "NanthAi Scribe/Meetings")
    }
    init(root: URL = MeetingRecorder.defaultRoot, defaults: UserDefaults = .standard) {
        store = MeetingStore(root: root); self.defaults = defaults
    }

    func load() async {
        do {
            try await store.purgeDeleted()
            let all = try await store.load()
            deletedMeetings = all.filter { $0.deletedAt != nil }
            let saved = all.filter { $0.deletedAt == nil }
            unreadableMeetings = await store.unreadable
            let currentIDs = Set(meetings.map(\.id))
            meetings += saved.filter { !currentIDs.contains($0.id) }
            meetings.sort { $0.startedAt > $1.startedAt }
            if selection == nil { selection = meetings.first?.id }
        } catch { self.error = error.localizedDescription }
    }

    /// Audio recorded straight into the meeting folder outlives a crash or force-quit; any
    /// meeting still marked recording or processing gets the finish pipeline on what exists.
    func recover(options: MeetingProcessingOptions) {
        for meeting in meetings where meeting.needsRecovery && meeting.id != recordingID && tasks[meeting.id] == nil {
            var resolved = options
            if !meeting.languages.isEmpty { resolved.languages = meeting.languages.map(Locale.init(identifier:)) }
            update(meeting.id) {
                $0 = MeetingPipeline.recover($0, folder: store.directory(meeting.id))
                $0.recovered = true
            }
            progress[meeting.id] = .init(identifiesSpeakers: ModelStore.isInstalled(ModelCatalog.meetingDiarizer, at: resolved.diarizer))
            processing.insert(meeting.id)
            let keep = keepAudio
            tasks[meeting.id] = Task { await finish(meeting.id, options: resolved, keepAudio: keep, captureErrors: []) }
        }
    }
    func importRecording(_ url: URL, dictation: Dictation, tellSpeakersApart: Bool = false) async {
        starting = true; error = nil
        defer { starting = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            if tellSpeakersApart { Task { try? await dictation.models.download(ModelCatalog.meetingDiarizer) } }
            let options = MeetingProcessingOptions(dictation: dictation)
            let metadata = try RecordingImport(url: url)
            let meeting = try await metadata.copy(from: url, into: store, languages: options.languages.map(\.identifier), keepAudio: keepAudio)
            meetings.insert(meeting, at: 0); selection = meeting.id
            progress[meeting.id] = .init(identifiesSpeakers: dictation.models.isInstalled(ModelCatalog.meetingDiarizer))
            processing.insert(meeting.id)
            let keep = keepAudio
            tasks[meeting.id] = Task { await finish(meeting.id, options: options, keepAudio: keep, captureErrors: []) }
        } catch { self.error = error.localizedDescription }
    }
    func requestStart() { showConsent = showReminder }

    func start(dictation: Dictation, tellSpeakersApart: Bool = false) async {
        await start(options: .init(dictation: dictation))
        if isRecording, tellSpeakersApart {
            Task {
                do { try await dictation.models.download(ModelCatalog.meetingDiarizer) }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    func togglePause() async {
        guard let session, !changingPause else { return }
        changingPause = true
        defer { changingPause = false }
        if paused { await session.resume() } else { await session.pause() }
        guard self.session === session else { return }
        paused = session.paused
        elapsed = session.elapsed
    }

    func start(options: MeetingProcessingOptions) async {
        guard !starting, !isRecording else { return }
        starting = true; error = nil
        defer { starting = false }
        guard await requestMicrophoneAccess() else { error = ScribeError.microphoneDenied.localizedDescription; return }
        let now = Date()
        var meeting = Meeting(title: "Meeting at " + now.formatted(date: .omitted, time: .shortened), startedAt: now,
                              appName: Self.frontmostAppName, state: .recording,
                              languages: options.languages.map(\.identifier))
        meeting.retainsAudio = keepAudio
        let session = MeetingCaptureSession(folder: store.directory(meeting.id), sources: makeSources())
        do {
            let apple = await LiveTranscriber.resolve(options.languages)
            if !apple.isEmpty { try await LiveTranscriber.prepareAssets(locales: options.languages) { [weak self] in self?.assetProgress = $0 } }
            if let first = options.languages.first, await !MeetingTranscriber.needsParakeet(first) {
                try await MeetingTranscriber.validate(locale: first, enabledLocales: options.languages) { [weak self] in
                    self?.assetProgress = $0
                }
            }
            try await store.save(meeting)
            try await session.start()
            meeting.audio = session.segments
            try await store.save(meeting)
            self.session = session; self.options = options; recordingID = meeting.id; elapsed = 0
            captureHealth = .healthy
            meetings.insert(meeting, at: 0); selection = meeting.id
            let id = meeting.id
            session.onChange = { [weak self, weak session] in
                guard let self, let session else { return }
                self.update(id) { $0.audio = session.segments }
            }
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, let session = self.session else { return }
                    self.elapsed = session.elapsed
                    await session.checkProgress()
                    if case .failed = session.health {
                        // The clock stops with the audio; Stop still keeps everything captured so far.
                        self.captureHealth = session.health
                        return
                    }
                }
            }
        } catch {
            _ = await session.stop()
            if session.segments.contains(where: { MeetingAudioFiles.hasAudio(store.directory(meeting.id).appending(path: $0.file)) }) {
                meeting.audio = session.segments; meeting.state = .processing
                meeting.processingError = error.localizedDescription
                meetings.insert(meeting, at: 0); selection = meeting.id
                try? await store.save(meeting)
            } else { try? await store.delete(meeting.id) }
            self.error = error.localizedDescription
        }
    }

    /// The app that was in front when recording started is usually the meeting app.
    private static var frontmostAppName: String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return app.localizedName
    }

    func stop() async {
        guard let session, let id = recordingID, let options else { return }
        progress[id] = .init(identifiesSpeakers: ModelStore.isInstalled(ModelCatalog.meetingDiarizer, at: options.diarizer))
        processing.insert(id)
        ticker?.cancel(); ticker = nil
        self.session = nil; recordingID = nil; captureHealth = .healthy; paused = false
        let captureErrors = await session.stop()
        let duration = session.elapsed
        update(id) { $0.endedAt = .now; $0.duration = duration; $0.state = .processing; $0.audio = session.segments }
        guard !quitting else { processing.remove(id); return }
        processing.insert(id)
        let retainAudio = keepAudio
        // Register work before the first suspension so Delete can cancel and await it safely.
        tasks[id] = Task { await finish(id, options: options, keepAudio: retainAudio, captureErrors: captureErrors) }
    }

    private func finish(_ id: UUID, options: MeetingProcessingOptions, keepAudio: Bool, captureErrors: [String]) async {
        defer { processing.remove(id); tasks[id] = nil }
        guard let meeting = meetings.first(where: { $0.id == id }) else { return }
        let folder = store.directory(id)
        var errors = captureErrors
        progress[id, default: .init(identifiesSpeakers: false)][.saving] = errors.isEmpty ? .done : .failed(errors.joined(separator: "\n"))
        progress[id]?[.transcribing] = .active
        // A crash can leave a header-only file; only segments with frames take part.
        let segments = meeting.audio.filter { MeetingAudioFiles.hasAudio(folder.appending(path: $0.file)) }
        let duration = segments.map { $0.offset + (MeetingAudioFiles.duration(of: folder.appending(path: $0.file)) ?? 0) }.max() ?? 0
        update(id) {
            $0.state = .processing
            $0.duration = max($0.duration, duration)
            if $0.endedAt == nil { $0.endedAt = $0.startedAt.addingTimeInterval($0.duration) }
        }
        guard !segments.isEmpty else {
            let message = (errors + ["Recording was interrupted."]).joined(separator: "\n")
            progress[id]?[.transcribing] = .failed(message)
            update(id) { $0.state = .done; $0.processingError = message }
            return
        }
        let transcript: MeetingPipeline.Transcript
        do {
            transcript = try await MeetingPipeline.transcribe(segments, folder: folder, languages: options.languages,
                parakeetDirectory: options.parakeet, diarizerDirectory: options.diarizer,
                enabledLocales: defaults.stringArray(forKey: "languages")?.map(Locale.init(identifier:)) ?? options.languages,
                progress: { [weak self] step, status in
                    await self?.setProgress(id, step: step, status: status)
                })
        } catch {
            guard !Task.isCancelled else { return }
            update(id) { $0.processingError = error.localizedDescription; $0.state = .done }
            progress[id]?[.transcribing] = .failed(error.localizedDescription)
            return
        }
        errors += transcript.errors
        let turns = transcript.turns
        update(id) {
            $0.replaceTranscript(turns)
            $0.processingError = turns.isEmpty ? "Couldn't transcribe. Your recording is kept for Retry." : (errors.isEmpty ? nil : errors.joined(separator: "\n"))
            $0.state = .done
        }
        if errors.isEmpty && !turns.isEmpty {
            // Commit the transcript before removing its only audio source, even if a queued save failed.
            await saving?.value
            do {
                if let snapshot = meetings.first(where: { $0.id == id }) {
                    try await store.save(snapshot)
                    try Task.checkCancellation()
                    await retainOrDeleteAudio(id, segments: segments, folder: folder, keepAudio: meeting.shouldKeepAudio(fallback: keepAudio))
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                progress[id]?[.saving] = .failed(error.localizedDescription)
            }
        }
        guard !Task.isCancelled else { return }
        if options.summarize { await summarize(id, gemma: options.gemma) }
        guard !Task.isCancelled else { return }
        update(id) { $0.state = .done }
    }

    /// Audio is only removed (or compressed) once a transcript exists; a failed finish keeps the originals.
    private func retainOrDeleteAudio(_ id: UUID, segments: [MeetingAudioSegment], folder: URL, keepAudio: Bool) async {
        var kept: [MeetingAudioSegment] = []
        var problems: [String] = []
        for segment in segments {
            let source = folder.appending(path: segment.file)
            if keepAudio {
                var compressed = segment
                compressed.file = (segment.file as NSString).deletingPathExtension + ".m4a"
                let destination = folder.appending(path: compressed.file)
                let outcome = await Task.detached(priority: .utility) { Result { try MeetingAudioFiles.compress(source, to: destination) } }.value
                switch outcome {
                case .success: kept.append(compressed)
                case .failure(let error): kept.append(segment); problems.append(error.localizedDescription)
                }
            } else { try? FileManager.default.removeItem(at: source) }
        }
        for segment in Set(meetings.first { $0.id == id }?.audio ?? []).subtracting(segments) {
            try? FileManager.default.removeItem(at: folder.appending(path: segment.file))
        }
        update(id) { $0.audio = kept; if !problems.isEmpty { $0.processingError = problems.joined(separator: "\n") } }
    }

    private func setProgress(_ id: UUID, step: MeetingProgress.Step, status: MeetingProgress.Status) {
        if step == .speakers { progress[id]?.identifiesSpeakers = true }
        progress[id]?[step] = status
    }
    func retryTranscription(_ id: UUID, dictation: Dictation) {
        guard !processing.contains(id), recordingID != id,
              var meeting = meetings.first(where: { $0.id == id }), meeting.beginRetry() else { return }
        update(id) { $0 = meeting }
        var options = MeetingProcessingOptions(dictation: dictation)
        if !meeting.languages.isEmpty { options.languages = meeting.languages.map(Locale.init(identifier:)) }
        progress[id] = .init(identifiesSpeakers: ModelStore.isInstalled(ModelCatalog.meetingDiarizer, at: options.diarizer))
        processing.insert(id)
        let keep = keepAudio
        tasks[id] = Task { await finish(id, options: options, keepAudio: keep, captureErrors: []) }
    }
    func regenerate(_ id: UUID, dictation: Dictation) {
        guard !processing.contains(id), recordingID != id else { return }
        let gemma = dictation.engine == .gemma && dictation.models.isInstalled(ModelCatalog.gemma)
            ? dictation.models.directory(for: ModelCatalog.gemma) : nil
        progress[id] = .init(identifiesSpeakers: false, statuses: [.saving: .done, .transcribing: .done])
        processing.insert(id)
        tasks[id] = Task {
            defer { processing.remove(id); tasks[id] = nil }
            await summarize(id, gemma: gemma)
        }
    }
    private func summarize(_ id: UUID, gemma: URL?) async {
        guard !quitting, let meeting = meetings.first(where: { $0.id == id }) else { return }
        progress[id]?[.summarising] = .active
        // No speech is an ordinary short recording, not a model failure.
        guard meeting.turns.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            update(id) { $0.summary = .init(bullets: []); $0.summaryError = nil }
            progress[id]?[.summarising] = .done
            return
        }
        summarizing.insert(id)
        defer { summarizing.remove(id) }
        do {
            let summarizer = MeetingSummarizer(gemma: gemma.map { GemmaRewriter(modelDirectory: $0) })
            let summary = try await summarizer.summarize(meeting)
            try Task.checkCancellation()
            update(id) { $0.summary = summary; $0.summaryError = nil; $0.summaryNeedsUpdate = $0.turns != meeting.turns }
            progress[id]?[.summarising] = .done
        } catch {
            guard !Task.isCancelled else { return }
            update(id) { $0.summaryError = "Couldn't update the summary. Try again." }
            progress[id]?[.summarising] = .failed("Couldn't update the summary. Try again.")
        }
    }
    func update(_ id: UUID, _ change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        change(&meetings[index])
        meetings[index].modified = .now
        let snapshot = meetings[index], previous = saving
        saving = Task {
            await previous?.value
            do { try await store.save(snapshot) } catch { self.error = error.localizedDescription }
        }
    }
    /// Title keystrokes change the list immediately but reach disk only once typing pauses.
    func updateTitle(_ id: UUID, _ title: String) {
        guard let index = meetings.firstIndex(where: { $0.id == id }), meetings[index].title != title else { return }
        meetings[index].title = title
        meetings[index].modified = .now
        titleSave?.cancel()
        if let pendingTitle, pendingTitle != id { update(pendingTitle) { _ in } }
        pendingTitle = id
        titleSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.flushTitle()
        }
    }
    private func flushTitle() {
        titleSave?.cancel(); titleSave = nil
        guard let pendingTitle else { return }
        self.pendingTitle = nil
        update(pendingTitle) { _ in }
    }
    func updateNotes(_ id: UUID, _ notes: String) {
        guard let index = meetings.firstIndex(where: { $0.id == id }), meetings[index].notes != notes else { return }
        meetings[index].notes = notes
        meetings[index].modified = .now
        notesSaves[id]?.cancel()
        notesSaves[id] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.flushNotes(id)
        }
    }
    private func flushNotes(_ id: UUID) {
        notesSaves.removeValue(forKey: id)?.cancel()
        update(id) { _ in }
    }
    /// Title and transcript, built once per meeting rather than on every search keystroke.
    func searchText(for meeting: Meeting) -> String {
        if let cached = searchCache[meeting.id] { return cached }
        let text = meeting.title + "\n" + meeting.notes + "\n" + MeetingExport.transcript(meeting)
        searchCache[meeting.id] = text
        return text
    }
    func restore(_ id: UUID, options: MeetingProcessingOptions? = nil) async {
        guard var meeting = deletedMeetings.first(where: { $0.id == id }) else { return }
        meeting.deletedAt = nil; meeting.modified = .now
        do {
            try await store.save(meeting)
            deletedMeetings.removeAll { $0.id == id }; meetings.append(meeting)
            meetings.sort { $0.startedAt > $1.startedAt }
            if meeting.needsRecovery, let options { recover(options: options) }
        } catch { self.error = error.localizedDescription }
    }
    func deleteNow(_ id: UUID) async {
        do { try await store.delete(id); deletedMeetings.removeAll { $0.id == id } }
        catch { self.error = error.localizedDescription }
    }
    func backupMeetings() async -> [Meeting] {
        for id in Array(notesSaves.keys) { flushNotes(id) }
        flushTitle()
        await saving?.value
        return meetings
    }
    func mergeBackupMeetings(_ incoming: [Meeting]) async throws {
        await saving?.value
        let merged = BackupMerge.items(meetings + deletedMeetings, incoming, modified: { $0.modified })
        for meeting in merged { try await store.save(meeting) }
        meetings = merged.filter { $0.deletedAt == nil }.sorted { $0.startedAt > $1.startedAt }
        deletedMeetings = merged.filter { $0.deletedAt != nil }
    }
    func delete(_ id: UUID) async {
        if recordingID == id { await stop() }
        notesSaves.removeValue(forKey: id)?.cancel()
        progress[id] = nil
        let task = tasks[id]; task?.cancel(); await task?.value
        await saving?.value
        do {
            if var meeting = meetings.first(where: { $0.id == id }) {
                meeting.deletedAt = .now; meeting.modified = .now
                try await store.save(meeting); deletedMeetings.append(meeting)
            } else { try await store.delete(id) }
            unreadableMeetings.removeAll { $0.id == id }
            meetings.removeAll { $0.id == id }
            if selection == id { selection = meetings.first?.id }
        } catch { self.error = error.localizedDescription }
    }
    /// Flushes audio and the meeting file, then lets the app go: transcription and summary
    /// resume through `recover` on the next launch instead of holding Quit for minutes.
    func finishBeforeQuit() async {
        quitting = true
        await stop()
        for task in tasks.values { task.cancel() }
        for task in Array(tasks.values) { await task.value }
        flushTitle()
        for id in Array(notesSaves.keys) { flushNotes(id) }
        await saving?.value
    }
}
