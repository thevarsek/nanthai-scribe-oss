import AppKit
import Observation
import os
import Speech
import ScribeCore
import ScribeUI
import ScribeMacCore

/// One shortcut-controlled utterance: capture → finalize → clean → optionally rewrite
/// → paste into the focused app.
@MainActor
@Observable
final class Dictation {
    enum Phase: Equatable {
        case idle, starting, listening, finishing, rewriting
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var liveText = ""
    private(set) var volatileText = ""
    private(set) var level: Float = 0
    var history: [DictationEntry] { historyStore.entries }
    var deletedNotes: [Note] { historyStore.deleted }
    func restoreNote(_ id: UUID) { historyStore.restore(id) }
    func deleteNoteNow(_ id: UUID) { historyStore.deleteNow(id) }
    @ObservationIgnored var insertText: (String, Bool) -> Void = { TextInserter.insert($0, replacingSelection: $1) }
    private var historyStore: DictationHistory
    var unreadableNotes: [UnreadableItem] { historyStore.unreadable }
    func deleteUnreadableNote(_ id: UUID) { historyStore.deleteUnreadable(id) }
    func retrySaveNotes() { historyStore.retrySave() }
    var historyFailure: SaveFailure? { historyStore.saveFailure }
    private(set) var languageError: String?
    private(set) var assetProgress: Double?
    private(set) var retryTakes = RetainedDictation.load()
    private var retrying = false
    private var lastExpiryTask: Task<Void, Never>?
    var lastDictation: LastDictationRecovery? { historyStore.recoverableDictation() }
    func pasteLastDictation() {
        guard let last = lastDictation, !last.isExpired() else { return }
        insertText(last.text, false)
    }
    func retryTranscription(_ take: RetainedDictation) {
        guard !retrying else { return }
        retrying = true
        Task {
            defer { retrying = false }
            do {
                let batch = models.isInstalled(ModelCatalog.parakeet)
                    ? ParakeetTranscriber(modelDirectory: models.directory(for: ModelCatalog.parakeet)) : nil
                let text = TextCleanup.clean(try await take.transcribe(parakeet: batch, enabledLocales: languages.map(Locale.init(identifier:))), dictionary: dictionary)
                guard !text.isEmpty else { return }
                record(text)
                guard historyFailure == nil else { return }
                try take.remove()
                retryTakes = RetainedDictation.load()
            } catch { showErrorMessage("Couldn't transcribe. Your recording is kept for Retry.") }
        }
    }

    #if DEBUG
    func previewFailedVoiceEdit(_ text: String) {
        let session = Session(outputLanguage: nil, dictionary: [], app: .init(), tone: .natural)
        self.session = session
        deliver(text, editing: true, session: session, error: RewriteError.timedOut)
    }
    func previewReliability(error: String? = nil, progress: Double? = nil, languageError: String? = nil, takes: [RetainedDictation]? = nil) {
        if let error { phase = .failed(error) }
        if let takes { retryTakes = takes }
        if progress != nil { phase = .starting }
        assetProgress = progress
        self.languageError = languageError
    }
    /// Offscreen visual fixtures exercise the real HUD without arming audio or the hotkey.
    func previewLiveText(_ text: String, volatile: String) {
        phase = .listening
        liveText = text
        volatileText = volatile
        level = 0.45
    }

    /// Performance fixtures replay mic levels so the HUD sees the same redraw mix as live use.
    func previewLevel(_ value: Float) {
        level = value
    }
    #endif

    // MARK: HUD presentation (layout in HUD.swift, states in docs/DESIGN.md §Mac — HUD)

    /// Chips shown above the text for the current utterance.
    var modes: [ScribeMode] {
        guard !isFailed, phase != .idle else { return [] }
        var modes: [ScribeMode] = []
        if shortcuts.polish { modes.append(isEditing ? .editSelection : .polish) }
        if shortcuts.handsFree { modes.append(.handsFree) }
        if shortcuts.polish, !isEditing, let output = session?.outputLanguage {
            modes.append(.translate(SpeechLanguage.languageName(Locale(identifier: output))))
        }
        return modes
    }
    /// Small line under the text, e.g. "Return to finish · Esc to cancel".
    var hint: String? {
        guard phase == .starting || phase == .listening else { return nil }
        if shortcuts.handsFree { return "Return to finish · Esc to cancel" }
        return isEditing ? "Release to apply" : nil
    }
    var listeningPlaceholder: String { isEditing ? "Say what to change" : "Listening…" }
    /// Replaces the text with a shimmer while a rewrite runs, e.g. "Refining…".
    var busyLabel: String? {
        guard phase == .rewriting else { return nil }
        return isEditing ? "Editing…" : "Refining…"
    }
    private var isEditing: Bool { shortcuts.polish && selectedText != nil }

    var talkShortcut: TalkShortcut {
        didSet {
            settings.talkShortcut = talkShortcut
            pushToTalk.shortcut = talkShortcut
            if oldValue != talkShortcut, pushToTalk.isRunning {
                // End a live hold before replacing its physical key state.
                end()
                pushToTalk.start()
            }
        }
    }
    var talkKey: TalkKey {
        get { if case .modifier(let key) = talkShortcut { key } else { .rightOption } }
        set { talkShortcut = .modifier(newValue) }
    }
    @discardableResult
    func captureTalkShortcut(_ capture: ((CGEvent) -> Void)?) -> Bool {
        if capture != nil { end() }
        pushToTalk.isRecordingShortcut = capture != nil
        pushToTalk.recordEvent = capture
        return pushToTalk.isRunning
    }
    /// Languages the user dictates in (speech-locale identifiers). With more than one, each
    /// utterance runs through all of them and the best transcript wins — see `LanguagePicker`.
    private(set) var languages: [String] = []
    /// Every language the on-device recognizer supports, for the menu.
    private(set) var availableLanguages: [Locale] = []
    /// Last language that won; its live text is shown while talking.
    private var lastDetected: String?

    /// nil keeps the spoken language; only chosen dictation locales are offered.
    var outputLanguage: String? {
        didSet { defaults.set(outputLanguage, forKey: "outputLanguage") }
    }

    var tone: RewriteTone {
        didSet { defaults.set(tone.rawValue, forKey: "tone") }
    }
    let appStyles: AppStyleSettings
    let vocabulary: Vocabulary
    let learning: LearningModel
    let contacts: ContactsNames
    @ObservationIgnored private let correctionWatch = AXCorrectionWatch()
    @ObservationIgnored private var correctionTimeout: Task<Void, Never>?
    private(set) var correctionPrompt: CorrectionPair?
    private(set) var correctionAdded = false

    #if DEBUG
    func previewCorrection(_ pair: CorrectionPair?, added: Bool = false) {
        correctionPrompt = pair; correctionAdded = added
    }
    #endif

    func dismissCorrection() {
        if let correctionPrompt { learning.notNow(correctionPrompt) }
        hideCorrection()
    }

    func addCorrection() {
        guard let correctionPrompt, learning.add(correctionPrompt, to: vocabulary) else { return }
        self.correctionPrompt = nil
        correctionAdded = true
        correctionTimeout?.cancel()
        correctionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            self?.correctionAdded = false
        }
    }

    private func hideCorrection() {
        correctionTimeout?.cancel()
        correctionPrompt = nil; correctionAdded = false
    }

    private func offerCorrection(_ pair: CorrectionPair, canAsk: Bool) {
        guard learning.record(pair, canAsk: canAsk) else { return }
        correctionWatch.didPrompt()
        correctionPrompt = pair
        correctionTimeout?.cancel()
        correctionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.hideCorrection()
        }
    }

    var snippets: [Snippet] {
        get { vocabulary.snippets }
        set { vocabulary.snippets = newValue }
    }
    var dictionary: [DictionaryEntry] {
        get { vocabulary.dictionary }
        set { vocabulary.dictionary = newValue }
    }

    static var vocabularyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "NanthAi Scribe", directoryHint: .isDirectory)
    }

    static let maxLanguages = 3


    var soundsEnabled: Bool {
        didSet { settings.soundsEnabled = soundsEnabled }
    }
    var engine: RewriteEngine {
        didSet {
            settings.engine = engine
            if engine != oldValue { warmSpeechPath() }
        }
    }
    var useScreenContext: Bool {
        didSet { settings.useScreenContext = useScreenContext }
    }
    var historyRetention: HistoryRetention {
        didSet {
            settings.historyRetention = historyRetention
            historyStore.prune(retention: historyRetention)
        }
    }
    var hotkeyArmed: Bool { pushToTalk.isRunning }

    // MARK: Optional models (M4/M5)

    /// Explicit, user-initiated downloads only.
    let models = ModelStore()
    /// Languages only the Parakeet pack covers; empty until it's installed.
    private(set) var packLanguages: [Locale] = []
    private var parakeet: ParakeetTranscriber?
    private var gemma: GemmaRewriter?
    private var warmTask: Task<Void, Never>?

    private let pushToTalk = PushToTalk()
    private let defaults: UserDefaults
    private let settings: MacSettings
    private var shortcuts = DictationShortcuts()
    private var selectedText: String?
    private var session: Session?
    private var errorTask: Task<Void, Never>?

    /// Resources belong to an utterance, so stale async work cannot stop a newer mic
    /// or paste into the next session after a cancellation.
    @MainActor
    private final class Session {
        let microphone = Microphone()
        let transcriber = LiveTranscriber()
        let outputLanguage: String?
        let tone: RewriteTone
        var dictionary: [DictionaryEntry]
        var screenTerms: [String] = []
        var context = TextInserter.Context()
        var finishRequested = false
        /// The transcriber is running and the microphone is feeding it.
        var ready = false
        let timing = CaptureTiming()
        var task: Task<Void, Never>?
        var rewriteDeadline: Task<Void, Never>?
        var screenTask: Task<Void, Never>?
        var cardTask: Task<Void, Never>?
        var card = ScreenCardDelivery()
        var cardCutoffTask: Task<Void, Never>?
        var screenSnapshot: ScreenReader.Snapshot?
        var cardStarted = false

        init(outputLanguage: String?, dictionary: [DictionaryEntry], app: TextInserter.Context, tone: RewriteTone) {
            self.outputLanguage = outputLanguage
            self.context = app
            self.tone = tone
            self.dictionary = dictionary
        }
    }

    private static let logger = Logger(subsystem: "tech.nanthai.Scribe", category: "ScreenContext")

    init(defaults: UserDefaults = .standard, historyURL: URL = DictationHistory.defaultURL,
         availableLanguages: [Locale] = [], vocabularyDirectory: URL = Dictation.vocabularyDirectory,
         packLanguages: [Locale] = []) {
        self.defaults = defaults
        tone = RewriteTone(rawValue: defaults.string(forKey: "tone") ?? "") ?? .natural
        appStyles = AppStyleSettings(defaults: defaults)
        vocabulary = Vocabulary(directory: vocabularyDirectory, legacyDefaults: defaults)
        learning = LearningModel(directory: vocabularyDirectory)
        contacts = ContactsNames(defaults: defaults)
        self.availableLanguages = availableLanguages
        self.packLanguages = packLanguages
        let settings = MacSettings(defaults: defaults)
        self.settings = settings
        talkShortcut = settings.talkShortcut
        soundsEnabled = settings.soundsEnabled
        engine = settings.engine
        useScreenContext = settings.useScreenContext
        historyRetention = settings.historyRetention
        historyStore = DictationHistory(url: historyURL, retention: settings.historyRetention)
        languages = defaults.stringArray(forKey: "languages") ?? []
        let savedOutput = defaults.string(forKey: "outputLanguage")
        outputLanguage = savedOutput.flatMap { languages.contains($0) ? $0 : nil }
        defaults.set(outputLanguage, forKey: "outputLanguage")
        lastDetected = defaults.string(forKey: "lastDetected")

        pushToTalk.shortcut = talkShortcut
        pushToTalk.onChange = { [weak self] shortcuts, action in
            guard let self else { return }
            self.shortcuts = shortcuts
            if shortcuts.polish, let session = self.session {
                self.startCardIfNeeded(session)
                self.warmRewriterIfNeeded()
            }
            switch action {
            case .start: self.begin()
            case .finish: self.end()
            case .cancel: self.cancel()
            case nil: break
            }
        }
        correctionWatch.dictionary = { [weak self] in self?.dictionary ?? [] }
        correctionWatch.canAsk = { [weak self] in self?.phase == .idle }
        correctionWatch.candidate = { [weak self] pair, canAsk in self?.offerCorrection(pair, canAsk: canAsk) }
        scheduleLastDictationExpiry()
    }

    private func scheduleLastDictationExpiry() {
        lastExpiryTask?.cancel()
        guard let last = lastDictation else { return }
        let remaining = max(0, last.createdAt.addingTimeInterval(3_600).timeIntervalSinceNow)
        lastExpiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            _ = self?.historyStore.lastDictation()
        }
    }

    /// - Returns: whether the hotkey is live. False until Accessibility is granted.
    @discardableResult
    func arm() -> Bool {
        pushToTalk.isRunning || pushToTalk.start()
    }

    /// Loads supported languages and, on first run, defaults to the system's preferred ones.
    func loadLanguages() async {
        let installed = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
        packLanguages = await ParakeetTranscriber.appleUnsupportedLanguages.sorted { SpeechLanguage.name($0) < SpeechLanguage.name($1) }
        availableLanguages = await LiveTranscriber.supportedLocales.sorted {
            let first = installed.contains($0.identifier)
            let second = installed.contains($1.identifier)
            if first != second { return first }
            return SpeechLanguage.name($0) < SpeechLanguage.name($1)
        } + (models.isInstalled(ModelCatalog.parakeet) ? packLanguages : [])
        if languages.isEmpty {
            let preferred = await LiveTranscriber.resolve(Locale.preferredLanguages.map(Locale.init(identifier:)))
            let chosen = preferred.isEmpty ? await LiveTranscriber.resolve([Locale(identifier: "en_US")]) : preferred
            languages = chosen.prefix(Self.maxLanguages).map(\.identifier)
            defaults.set(languages, forKey: "languages")
        }
        warmSpeechPath()
    }

    func isSelected(_ locale: Locale) -> Bool { languages.contains(locale.identifier) }

    /// Adds or removes a language, keeping at least one and at most `maxLanguages`.
    func toggle(_ locale: Locale) {
        var next = languages
        if let index = next.firstIndex(of: locale.identifier) {
            guard next.count > 1 else { return }
            next.remove(at: index)
        } else {
            guard next.count < Self.maxLanguages else { return }
            next.append(locale.identifier)
        }
        setLanguages(next)
    }

    private func setLanguages(_ ids: [String]) {
        languages = ids
        if let outputLanguage, !ids.contains(outputLanguage) { self.outputLanguage = nil }
        defaults.set(ids, forKey: "languages")
        let locales = ids.map(Locale.init(identifier:))
        Task {
            do {
                try await LiveTranscriber.setLanguages(locales) { [weak self] in self?.assetProgress = $0 }
                languageError = nil
            } catch { languageError = "Couldn't prepare this language. Try again." }
            warmSpeechPath()
        }
    }

    func retryLanguages() { setLanguages(languages) }

    // MARK: - Optional models

    /// Pack languages are routed to Parakeet only; Apple's languages stay on the fast path.
    private var needsParakeet: Bool {
        let pack = Set(packLanguages.map(\.identifier))
        return languages.contains { pack.contains($0) }
    }

    private func parakeetEngine() -> ParakeetTranscriber? {
        guard needsParakeet, models.isInstalled(ModelCatalog.parakeet) else { return nil }
        if let parakeet { return parakeet }
        let engine = ParakeetTranscriber(modelDirectory: models.directory(for: ModelCatalog.parakeet))
        parakeet = engine
        return engine
    }

    /// The first Core ML load takes tens of seconds; do it before the user talks.
    private func warmParakeetIfNeeded() {
        guard let engine = parakeetEngine() else { return }
        Task.detached(priority: .utility) { _ = await engine.isAvailable() }
    }

    /// Warms what the first press would otherwise wait for: Apple's speech models, and the
    /// Parakeet model only when a pack language is selected. Low priority, no microphone, no
    /// downloads. The Gemma rewriter is not loaded here (several GB); see `warmRewriterIfNeeded`.
    private func warmSpeechPath() {
        warmParakeetIfNeeded()
        let locales = languages.map(Locale.init(identifier:))
        guard !locales.isEmpty else { return }
        warmTask?.cancel()
        warmTask = Task.detached(priority: .utility) {
            let start = ContinuousClock.now
            await LiveTranscriber.prewarm(locales: locales)
            let ms = CaptureTiming.milliseconds(from: start, to: .now)
            Logger(subsystem: "tech.nanthai.Scribe", category: "Latency")
                .info("speech prewarm: \(ms, privacy: .public) ms")
        }
    }

    /// A Refine press needs Gemma only after the user stops talking, so loading it while
    /// they speak hides the cold load without keeping it resident for plain dictation.
    private func warmRewriterIfNeeded() {
        guard engine == .gemma, shortcuts.polish, models.isInstalled(ModelCatalog.gemma) else { return }
        let rewriter = rewriter()
        Task.detached(priority: .utility) {
            let start = ContinuousClock.now
            _ = await rewriter.isAvailable()
            let ms = CaptureTiming.milliseconds(from: start, to: .now)
            Logger(subsystem: "tech.nanthai.Scribe", category: "Latency")
                .info("rewriter warm: \(ms, privacy: .public) ms")
        }
    }

    func rewriter() -> any TextRewriter {
        guard engine == .gemma, models.isInstalled(ModelCatalog.gemma) else { return AppleRewriter() }
        if let gemma { return gemma }
        let rewriter = GemmaRewriter(modelDirectory: models.directory(for: ModelCatalog.gemma))
        gemma = rewriter
        return rewriter
    }

    func download(_ model: ModelDescriptor) {
        Task {
            try? await models.download(model)
            if model == ModelCatalog.parakeet { await loadLanguages() }
        }
    }

    func pauseDownload(_ model: ModelDescriptor) {
        Task { await models.pause(model) }
    }

    func delete(_ model: ModelDescriptor) {
        Task {
            if model == ModelCatalog.parakeet {
                await parakeet?.unload()
                parakeet = nil
                let pack = Set(packLanguages.map(\.identifier))
                let kept = languages.filter { !pack.contains($0) }
                packLanguages = []
                if kept.count != languages.count { languages = kept; defaults.set(kept, forKey: "languages") }
            } else if model == ModelCatalog.gemma {
                await gemma?.unload()
                gemma = nil
            }
            try? await models.delete(model)
            if model == ModelCatalog.parakeet { await loadLanguages() }
        }
    }

    func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    @discardableResult
    func createNote(text: String = "", origin: Note.Origin = .typed) -> Note {
        let note = Note(text: text, origin: origin, isKept: true)
        historyStore.upsert(note)
        return note
    }

    func importNotes(_ notes: [Note]) { historyStore.importNotes(notes) }
    func saveNote(_ note: Note) { historyStore.upsert(note) }
    func deleteNote(_ id: UUID) { historyStore.delete(id) }

    func clearHistory(includePinned: Bool = false) {
        historyStore.clear(includePinned: includePinned)
    }

    // MARK: - Lifecycle

    private func begin() {
        guard phase == .idle || isFailed else { return }
        let keyDown = ContinuousClock.now
        hideCorrection()
        correctionWatch.stop()
        errorTask?.cancel()
        let app = NSWorkspace.shared.frontmostApplication
        let appContext = TextInserter.Context(appName: app?.localizedName, bundleID: app?.bundleIdentifier)
        let resolvedTone = AppStyleResolver.resolve(bundleID: appContext.bundleID,
            overrides: appStyles.overrides(defaultTone: tone), defaultTone: tone)
        let session = Session(outputLanguage: outputLanguage, dictionary: dictionary,
                              app: appContext, tone: resolvedTone)
        session.timing.keyDown = keyDown
        warmRewriterIfNeeded()
        self.session = session
        selectedText = nil
        phase = .starting
        liveText = ""
        volatileText = ""
        level = 0

        // Leave the event-tap callback before making AX or audio calls.
        session.task = Task { [weak self] in
            guard let self, self.session === session else { return }
            do {
                // Capture first: everything below can take seconds on a cold start, and the
                // user is already talking. The audio waits in the microphone's pre-roll.
                if !Microphone.accessGranted {
                    guard await Microphone.requestAccess() else { throw ScribeError.microphoneDenied }
                    guard self.session === session, !Task.isCancelled else { return }
                }
                try session.microphone.startCapture(onLevel: Self.levelCallback(self, session: session))
                session.timing.mark(.micRunning)
                phase = .listening
                play("Tink")

                try? await session.transcriber.setContext(contextualStrings:
                    DictionaryEntry.contextualStrings(in: session.dictionary))
                guard self.session === session, !Task.isCancelled else { return }
                if useScreenContext, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    startScreenContext(session, processIdentifier: pid)
                }
                session.context = TextInserter.context(app: session.context)
                selectedText = session.context.selection
                session.transcriber.onUpdate = { [weak self, weak session] text in
                    guard let self, let session, self.session === session else { return }
                    if !text.isEmpty { session.timing.mark(.firstResult) }
                    self.liveText = text
                    self.volatileText = session.transcriber.volatileText
                }
                try? await session.transcriber.setContext(contextualStrings:
                    DictionaryEntry.contextualStrings(in: session.dictionary, screenTerms: session.screenTerms))
                session.transcriber.onAssetProgress = { [weak self] in self?.assetProgress = $0 }
                let (format, sink) = try await session.transcriber.start(
                    locales: languages.map(Locale.init(identifier:)),
                    displayLocale: lastDetected.map(Locale.init(identifier:)),
                    batchEngines: parakeetEngine().map { [$0] } ?? []
                )
                guard self.session === session, !Task.isCancelled else {
                    await session.transcriber.cancel()
                    return
                }
                session.timing.mark(.transcriberReady)
                // Released while the analyzer was starting: keep the pre-roll if it holds speech.
                let spoke = session.microphone.bufferedSeconds >= 0.3 && session.microphone.peakLevel > 0.15
                if session.finishRequested, spoke {
                    session.microphone.attach(format: format, sink: sink)
                    session.ready = true
                    finish(session)
                    return
                }
                if session.finishRequested {
                    // A tap with no speech has no audio to finalize.
                    session.microphone.stop()
                    level = 0
                    await session.transcriber.cancel()
                    guard self.session === session else { return }
                    if SelectionRefine.request(speech: "", selection: session.context.selection, polish: shortcuts.polish) != nil {
                        finish(session)
                    } else { complete(session) }
                    return
                }
                session.microphone.attach(format: format, sink: sink)
                session.ready = true
                if phase != .listening { phase = .listening }
            } catch {
                guard self.session === session else { return }
                fail(error)
            }
        }
    }

    private func end() {
        guard let session else { return }
        session.card.release(at: .now)
        session.cardCutoffTask = Task { [weak session] in
            do { try await Task.sleep(for: .milliseconds(1_500)) } catch { return }
            session?.cardTask?.cancel()
        }
        switch phase {
        case .starting: session.finishRequested = true
        case .listening where !session.ready: session.finishRequested = true
        case .listening: finish(session)
        default: break
        }
    }

    private func finish(_ session: Session) {
        phase = .finishing
        session.microphone.stop()
        level = 0
        let editing = isEditing
        let polish = shortcuts.polish

        session.task = Task { [weak self] in
            guard let self else { return }
            let (raw, detected) = await session.transcriber.finish(keepingAudioUntilDelivery: true)
            guard self.session === session, !Task.isCancelled else { return }
            // Contact names stay local to this take: never speech bias, never saved.
            let dictionary = session.dictionary + contacts.matches(in: raw, languages: languages).filter { contact in
                !session.dictionary.contains { $0.term.caseInsensitiveCompare(contact.term) == .orderedSame }
            }
            let cleaned = TextCleanup.clean(raw, dictionary: dictionary)
            let snippets = self.snippets
            let exact = editing ? nil : Snippets.exactMatch(in: raw, snippets: snippets)
            let silentSelection = SelectionRefine.request(speech: cleaned, selection: session.context.selection, polish: polish)
            guard !cleaned.isEmpty || exact != nil || silentSelection != nil else {
                retryTakes = RetainedDictation.load()
                complete(session)
                return
            }
            if let detected {
                lastDetected = detected.identifier
                defaults.set(detected.identifier, forKey: "lastDetected")
            }

            var text = exact ?? cleaned
            var rewriteError: Error?
            if polish && exact == nil {
                phase = .rewriting
                // The model's own timeout cancels generation. Keep a delivery deadline
                // too: structured model teardown must not delay the fallback paste.
                if editing || cleaned.count <= 2_500 {
                    session.rewriteDeadline = Task { [weak self, weak session] in
                        do { try await Task.sleep(for: .seconds(20)) } catch { return }
                        guard let self, let session, self.session === session else { return }
                        session.task?.cancel()
                        deliver(Snippets.expand(in: cleaned, snippets: snippets), editing: editing, session: session, error: RewriteError.timedOut)
                    }
                }
                let card = await screenCard(for: session)
                guard self.session === session, !Task.isCancelled else { return }
                let request = RewriteRequest(
                    task: silentSelection?.task ?? (editing
                        ? .edit(instruction: cleaned, selection: session.context.selection ?? "")
                        : .polish),
                    transcript: silentSelection?.transcript ?? cleaned,
                    spokenLanguage: detected,
                    context: RewriteContext(
                        draftBefore: session.context.draftBefore,
                        screenCard: card,
                        appName: session.context.appName,
                        // Edit follows its spoken instruction, including translations.
                        outputLanguage: editing ? nil : session.outputLanguage.map(Locale.init(identifier:)),
                        tone: session.tone,
                        dictionaryTerms: DictionaryEntry.terms(in: dictionary)
                    )
                )
                do {
                    let rewritten = try await ChunkedRewriter(rewriter()).rewrite(request)
                    text = DictionaryReplacement.apply(to: rewritten, dictionary: dictionary)
                } catch {
                    rewriteError = error
                }
            }
            // Cancellation can arrive during either finalization or model generation.
            guard self.session === session, !Task.isCancelled else { return }
            deliver(exact ?? Snippets.expand(in: text, snippets: snippets), editing: editing, session: session, error: rewriteError)
        }
    }

    private func startScreenContext(_ session: Session, processIdentifier: pid_t) {
        session.screenTask = Task { [weak self, weak session] in
            let start = ContinuousClock.now
            let snapshot = await ScreenReader.read(processIdentifier: processIdentifier)
            let readMS = Self.milliseconds(since: start)
            guard let self, let session, self.session === session, !Task.isCancelled else { return }
            session.screenSnapshot = snapshot
            startCardIfNeeded(session)
            session.card.fallback = ContextDistiller.fallback(terms: [], nearCursor: snapshot.nearCursor, cursorOffset: snapshot.cursorOffset)
            let termsTask = Task.detached(priority: .userInitiated) {
                ScreenTerms.extract(from: snapshot.text, nearCursor: snapshot.nearCursor, cursorOffset: snapshot.cursorOffset)
            }
            let terms = await withTaskCancellationHandler { await termsTask.value } onCancel: { termsTask.cancel() }
            guard self.session === session, !Task.isCancelled else { return }
            Self.logger.debug("Screen read ms: \(readMS, privacy: .public); terms: \(terms.count, privacy: .public)")
            session.card.fallback = ContextDistiller.fallback(terms: terms, nearCursor: snapshot.nearCursor, cursorOffset: snapshot.cursorOffset)
            session.card.termsFinished = true
            // Bias failure must not discard a dictation or prevent recording.
            session.screenTerms = terms
            try? await session.transcriber.setContext(contextualStrings:
                DictionaryEntry.contextualStrings(in: session.dictionary, screenTerms: terms))
        }
    }

    /// The card costs a Foundation Models run, so it's only distilled once Refine/Edit is
    /// requested — at the chord, or when the window read lands if the chord came first.
    private func startCardIfNeeded(_ session: Session) {
        guard shortcuts.polish, !session.cardStarted, let snapshot = session.screenSnapshot else { return }
        session.cardStarted = true
        guard !snapshot.text.isEmpty || snapshot.nearCursor != nil,
              session.card.deadline.map({ ContinuousClock.now < $0 }) ?? true else {
            session.card.finish(nil, at: .now)
            return
        }
        session.cardTask = Task { [weak self, weak session] in
            let start = ContinuousClock.now
            let card = try? await ContextDistiller().distill(snapshot.text.isEmpty ? snapshot.nearCursor ?? "" : snapshot.text)
            guard let self, let session, self.session === session, !Task.isCancelled else { return }
            session.card.finish(card, at: .now)
            let cardMS = Self.milliseconds(since: start)
            Self.logger.debug("Screen card ms: \(cardMS, privacy: .public)")
        }
    }

    private func screenCard(for session: Session) async -> String? {
        guard session.screenTask != nil else { return nil }
        while session.card.shouldWait(at: .now), !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return nil }
        }
        let card = session.card.result
        session.cardTask?.cancel()
        return card
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private func deliver(_ text: String, editing: Bool, session: Session, error: Error?) {
        guard self.session === session else { return }
        if editing, text.isEmpty {
            retryTakes = RetainedDictation.load()
            complete(session)
            if let error { showErrorMessage(DictationFailure.rewrite(error, editing: true)) }
            return
        }
        if !DictationFailure.shouldInsert(editing: editing, rewriteFailed: error != nil), let error {
            // Preserve the instruction for recovery without touching the selected text.
            record(text)
            if historyFailure == nil { session.transcriber.discardRetainedTake() }
            retryTakes = RetainedDictation.load()
            complete(session)
            showErrorMessage(DictationFailure.rewrite(error, editing: true))
            return
        }
        let correctionTarget = AXCorrectionWatch.capture(inserted: text, replacingSelection: editing)
        insertText(text, editing)
        if let correctionTarget { correctionWatch.start(correctionTarget) }
        record(text)
        if historyFailure == nil { session.transcriber.discardRetainedTake() }
        retryTakes = RetainedDictation.load()
        play("Pop")
        complete(session)
        if let error { showErrorMessage(DictationFailure.rewrite(error, editing: false)) }
    }

    private func cancel() {
        guard let session else { return }
        self.session = nil
        session.task?.cancel()
        session.rewriteDeadline?.cancel()
        session.screenTask?.cancel()
        session.cardTask?.cancel()
        session.cardCutoffTask?.cancel()
        session.microphone.stop()
        Task { await session.transcriber.cancel() }
        level = 0
        liveText = ""
        volatileText = ""
        selectedText = nil
        phase = .idle
    }

    private func complete(_ session: Session) {
        guard self.session === session else { return }
        self.session = nil
        session.task = nil
        session.screenTask?.cancel()
        session.cardTask?.cancel()
        session.cardCutoffTask?.cancel()
        session.rewriteDeadline?.cancel()
        session.rewriteDeadline = nil
        pushToTalk.complete()
        selectedText = nil
        phase = .idle
        liveText = ""
        volatileText = ""
    }

    private func fail(_ error: Error) {
        cancel()
        pushToTalk.complete()
        showError(error)
    }

    private func showError(_ error: Error) {
        showErrorMessage(error.localizedDescription)
    }

    private func showErrorMessage(_ message: String) {
        phase = .failed(message)
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard let self, isFailed else { return }
            phase = .idle
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func smooth(_ new: Float) {
        guard phase == .listening || phase == .starting else { return }
        level += (new - level) * 0.4
    }

    private nonisolated static func levelCallback(_ owner: Dictation, session: Session) -> @Sendable (Float) -> Void {
        { [weak owner, weak session] level in
            Task { @MainActor in
                guard let owner, let session, owner.session === session else { return }
                owner.smooth(level)
            }
        }
    }

    private func play(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    // MARK: - History

    private func record(_ text: String) {
        historyStore.insert(text, retention: historyRetention)
        scheduleLastDictationExpiry()
    }
}
