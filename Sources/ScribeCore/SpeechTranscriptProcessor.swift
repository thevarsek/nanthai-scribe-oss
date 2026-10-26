import Foundation
import Synchronization

/// Recognition, sentence monitoring and serialized span retries never occupy the HUD's
/// executor. Publication alone is coalesced; completed revisions and final text survive it.
actor SpeechTranscriptProcessor {
    struct Snapshot: Sendable { let revision: Int; let text: String; let volatileText: String; let audioEnd: Double }
    struct Event: Sendable {
        let text: AttributedString
        let isFinal: Bool
        let start: Double
        let end: Double
        let index: Int
        let generation: Int
    }
    private var lanes: [SpeechLane]
    private let locales: [Locale]
    private var languageLock = SpeechLanguageLock()
    private var active: Int?
    private var generation = 0
    private var floor = -Double.infinity
    private var document = SpeechTranscriptDocument()
    private var monitor = SpeechSentenceMonitor(baseline: 0)
    private let displayIndex: Int
    private let measure: (@Sendable (SpeechPerformanceSample) -> Void)?
    private let update: @MainActor @Sendable (Snapshot) -> Void
    private let clip: @Sendable (Double, Double) async throws -> SpeechAudioStore.Clip
    private let replay: @Sendable (URL, Locale, [String]) async throws -> SpeechLane
    private let switchLane: @MainActor @Sendable (Int, Int, Double) async -> Bool
    private var context: [String] = []
    private var revision = 0
    private var lastAudioEnd = 0.0
    private var volatileStart = 0.0
    private var pending: Snapshot?
    nonisolated private let latest = Mutex<Snapshot?>(nil)
    nonisolated var latestSnapshot: Snapshot? { latest.withLock { $0 } }
    private var publication: Task<Void, Never>?
    private var recheckTask: Task<Void, Never>?
    private var retry: Task<SpeechLane, Error>?
    private var queue: [Int] = []
    private var queueHead = 0
    private var queuedAt: [Int: ContinuousClock.Instant] = [:]
    private var confirmed = 1
    private var lastFlip: Int?
    private var consecutiveFlips = 0
    private var handoff: (index: Int, generation: Int, events: [Event])?
    private var cancelled = false
    private var inputEnded = false
    private var finishing = false

    init(locales: [Locale], displayIndex: Int, measure: (@Sendable (SpeechPerformanceSample) -> Void)?,
         clip: @escaping @Sendable (Double, Double) async throws -> SpeechAudioStore.Clip,
         replay: (@Sendable (URL, Locale, [String]) async throws -> SpeechLane)? = nil,
         switchLane: @escaping @MainActor @Sendable (Int, Int, Double) async -> Bool,
         update: @escaping @MainActor @Sendable (Snapshot) -> Void) {
        self.locales = locales
        lanes = locales.map { SpeechLane(locale: $0) }
        self.displayIndex = displayIndex
        self.measure = measure
        self.clip = clip
        self.replay = replay ?? { url, locale, strings in
            try await SpeechFileTranscriber.transcribe(file: url, locale: locale, contextualStrings: strings, measure: measure)
        }
        self.switchLane = switchLane
        self.update = update
    }

    func setContext(_ strings: [String]) { context = strings }
    func endInput() { inputEnded = true }

    func apply(_ event: Event) -> Int? {
        guard !cancelled else { return nil }
        guard event.generation == generation else {
            if handoff?.index == event.index, handoff?.generation == event.generation { handoff?.events.append(event) }
            return nil
        }
        guard active == nil || active == event.index else { return nil }
        lastAudioEnd = max(lastAudioEnd, event.end)
        let start = ContinuousClock.now
        defer { record("apply", since: start, audioEnd: event.end) }
        lanes[event.index].apply(event.text, isFinal: event.isFinal,
                                 countWords: locales.count > 1 && (active == nil || event.isFinal))
        if !event.isFinal { volatileStart = event.start }
        var newlyLocked: Int?
        if locales.count > 1 {
            if active == nil, let locked = languageLock.consider(lanes, audioEnd: event.end) {
                active = locked
                monitor = SpeechSentenceMonitor(baseline: lanes[locked].confidenceCount > 0 ? languageLock.earlyConfidence : 0)
                document.seed(lanes[locked], source: locked, end: lanes[locked].tokens.last?.end ?? event.end)
                confirmed = document.segments.count
                newlyLocked = locked
                if measure != nil {
                    for index in languageLock.probeScores.indices {
                        record("probe_\(locales[index].identifier)_score_\(Int(languageLock.probeScores[index] * 1000))_words_\(languageLock.probeWords[index])", since: start, audioEnd: event.end)
                    }
                }
                record("lock_" + locales[locked].identifier, since: start, audioEnd: event.end)
            } else if let active, event.isFinal {
                let timed = LiveTranscriber.timedTokens(event.text)
                let tokens: [SpeechToken]
                if timed.complete, !timed.tokens.isEmpty { tokens = timed.tokens }
                else {
                    let confidences = event.text.runs.compactMap(\.transcriptionConfidence)
                    tokens = [.init(text: String(event.text.characters), start: event.start, end: event.end,
                                    confidence: confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count))]
                }
                for id in document.append(tokens, source: active, floor: floor) { assess(id) }
            }
        }
        publishLater()
        return newlyLocked
    }

    private func assess(_ id: Int) {
        let segment = document.segments[id]
        let start = ContinuousClock.now
        let suspicious = monitor.suspicious(segment, locale: locales[segment.source], among: locales)
        record("monitor", since: start, audioEnd: segment.end)
        if suspicious {
            queue.append(id)
            queuedAt[id] = .now
            record("spanQueued", since: start, audioEnd: segment.end)
            if recheckTask == nil {
                recheckTask = Task { [weak self] in await self?.drainRechecks() }
            }
        } else {
            document.resolve(id, candidate: .init(locale: locales[segment.source], text: segment.text,
                                                 confidence: segment.confidence), winner: segment.source)
        }
    }

    private func drainRechecks() async {
        while queueHead < queue.count, !cancelled, !Task.isCancelled {
            let id = queue[queueHead]
            queueHead += 1
            let segment = document.segments[id]
            let start = ContinuousClock.now
            var best = LanguagePicker.Candidate(locale: locales[segment.source], text: segment.text, confidence: segment.confidence)
            var winner = segment.source
            let languages = Set(locales.compactMap(LanguagePicker.language(for:)))
            var bestScore = LanguagePicker.score(best, among: languages)
            do {
                let audio = try await clip(segment.start, segment.end)
                defer { try? FileManager.default.removeItem(at: audio.url) }
                record(audio.fromRing ? "spanAudio_ring" : "spanAudio_file", since: start, audioEnd: segment.end)
                for index in locales.indices where index != segment.source {
                    guard !cancelled, !Task.isCancelled else { break }
                    let locale = locales[index], context = context
                    let work = Task { [replay] in try await replay(audio.url, locale, context) }
                    retry = work
                    let lane: SpeechLane
                    do { lane = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() } }
                    catch {
                        retry = nil
                        record("spanFailed_" + locale.identifier, since: start, audioEnd: segment.end)
                        continue
                    }
                    retry = nil
                    let tokens = lane.tokens.filter { $0.midpoint + audio.start >= segment.start && $0.midpoint + audio.start <= segment.end }
                    let candidate = tokens.isEmpty || !lane.hasTiming ? lane.candidate : LanguagePicker.Candidate(
                        locale: locale, text: MixedLanguageTranscript.joinTokens(tokens),
                        confidence: tokens.reduce(0) { $0 + $1.confidence } / Double(tokens.count))
                    let score = LanguagePicker.score(candidate, among: languages)
                    if !candidate.text.isEmpty, score - bestScore >= 0.15 { best = candidate; bestScore = score; winner = index }
                }
            } catch {
                record("spanFailed", since: start, audioEnd: segment.end)
            }
            guard !cancelled, !Task.isCancelled else { break }
            document.resolve(id, candidate: best, winner: winner)
            record("spanRecheck", since: start, audioEnd: segment.end)
            record("spanLatency", since: queuedAt.removeValue(forKey: id) ?? start, audioEnd: segment.end)
            if winner != segment.source { record("spanFlipped_" + locales[winner].identifier, since: start, audioEnd: segment.end) }
            publishLater()
            await advanceDecisions()
        }
        queue = []
        queueHead = 0
        recheckTask = nil
    }

    private func advanceDecisions() async {
        while confirmed < document.segments.count, let winner = document.segments[confirmed].winner {
            let segment = document.segments[confirmed]
            confirmed += 1
            if winner == segment.source { consecutiveFlips = 0; lastFlip = nil; continue }
            consecutiveFlips = lastFlip == winner ? consecutiveFlips + 1 : 1
            lastFlip = winner
            guard consecutiveFlips >= 2, active != winner, !inputEnded, !finishing, let old = active else { continue }
            let savedDocument = document, oldGeneration = generation, oldFloor = floor
            handoff = (old, generation, [])
            generation += 1
            active = winner
            floor = document.boundary
            document.discardPendingForReplay()
            lanes[winner] = SpeechLane(locale: locales[winner])
            let switched = await switchLane(winner, generation, max(0, floor - 0.2))
            if switched {
                monitor = SpeechSentenceMonitor(baseline: segment.confidence)
                record("relock_" + locales[winner].identifier, since: .now, audioEnd: floor)
                handoff = nil
            } else {
                let buffered = handoff?.events ?? []
                handoff = nil
                active = old
                generation = oldGeneration
                floor = oldFloor
                document = savedDocument
                for event in buffered { _ = apply(event) }
            }
            consecutiveFlips = 0
            lastFlip = nil
            publishLater()
        }
    }

    private func publishLater() {
        let selected = active ?? displayIndex
        guard lanes.indices.contains(selected) else { return }
        let text: String
        if locales.count > 1, active != nil {
            text = MixedLanguageTranscript.joinText(MixedLanguageTranscript.joinText(document.text, document.pendingText), lanes[selected].volatile)
        } else { text = lanes[selected].text }
        revision += 1
        pending = Snapshot(revision: revision, text: text, volatileText: lanes[selected].volatile, audioEnd: lastAudioEnd)
        latest.withLock { $0 = pending }
        schedulePublication()
    }

    private func schedulePublication() {
        guard publication == nil, !cancelled, !finishing else { return }
        publication = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            await self?.publish()
        }
    }

    private func publish() async {
        guard !cancelled, let snapshot = pending else { publication = nil; return }
        pending = nil
        await update(snapshot)
        publication = nil
        if pending != nil { schedulePublication() }
    }

    func finish(batch: [LanguagePicker.Candidate]) async -> LanguagePicker.Candidate? {
        guard !cancelled else { return nil }
        inputEnded = true
        finishing = true
        publication?.cancel()
        publication = nil
        if let active {
            if !lanes[active].volatile.isEmpty {
                // A recognizer failure can end its stream before finalizing the tail.
                // Preserve the latest draft; volatile confidence is not monitoring evidence.
                let tail = SpeechToken(text: lanes[active].volatile, start: volatileStart,
                                       end: lastAudioEnd, confidence: 0.5)
                var ids = document.append([tail], source: active, floor: floor)
                if let id = document.flush(source: active) { ids.append(id) }
                for id in ids {
                    let segment = document.segments[id]
                    document.resolve(id, candidate: .init(locale: locales[active], text: segment.text,
                                                          confidence: segment.confidence), winner: active)
                }
            } else if let id = document.flush(source: active) { assess(id) }
        }
        await recheckTask?.value
        guard !cancelled, !Task.isCancelled else { return nil }
        let start = ContinuousClock.now
        let result: LanguagePicker.Candidate?
        if let active { result = LanguagePicker.best(of: [document.candidate(locales: locales, active: active)] + batch) }
        else { result = MixedLanguageTranscript.finalSelection(lanes: lanes, batch: batch) }
        record("finalSelection", since: start, audioEnd: lastAudioEnd)
        if let result {
            revision += 1
            let snapshot = Snapshot(revision: revision, text: result.text, volatileText: "", audioEnd: lastAudioEnd)
            latest.withLock { $0 = snapshot }
            pending = nil
            await update(snapshot)
        }
        return result
    }

    func cancel() {
        cancelled = true
        retry?.cancel(); retry = nil
        recheckTask?.cancel(); recheckTask = nil
        publication?.cancel(); publication = nil
        pending = nil
        queuedAt = [:]
    }

    private func record(_ phase: String, since start: ContinuousClock.Instant, audioEnd: Double) {
        let elapsed = start.duration(to: .now).components
        measure?(.init(phase: phase, audioEnd: audioEnd,
                      milliseconds: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
                      onMainThread: Thread.isMainThread))
    }
}
