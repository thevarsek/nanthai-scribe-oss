import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Opt-in timings contain no recognized text and do not write to the system log.
@_spi(Performance) public struct SpeechPerformanceSample: Sendable {
    public let phase: String
    public let audioEnd: Double
    public let milliseconds: Double
    public let onMainThread: Bool
}

public enum ScribeError: LocalizedError {
    case unsupportedLocale(Locale)
    case noAudioFormat
    case microphoneDenied
    case microphoneUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale):
            "On-device speech recognition doesn't support \(locale.identifier) yet."
        case .noAudioFormat:
            "No audio format is available for on-device speech recognition."
        case .microphoneDenied:
            "Microphone access is off. Turn it on in System Settings › Privacy & Security › Microphone."
        case .microphoneUnavailable:
            "The microphone couldn't be started."
        }
    }
}

/// One utterance of streaming, on-device speech-to-text, in one or more candidate languages.
///
/// Built on `SpeechAnalyzer` + `SpeechTranscriber`: no network, no bundled model (the OS
/// manages model assets). Apple's recognizer hears a single language, so for multilingual
/// users probe their chosen languages, then keep only the early winner running. Suspicious
/// finalized stretches are revised from short alternate-language passes; consecutive flips
/// move live recognition to that language. Create one per utterance: `start()`, push audio into the returned
/// continuation, then `finish()`.
@MainActor
public final class LiveTranscriber {
    /// Live text from the selected languages (finalized plus the still-revising tail).
    public private(set) var text = ""
    /// The suffix that can still be revised, so previews can distinguish it from committed words.
    public private(set) var volatileText = ""
    public var onUpdate: ((String) -> Void)?
    public var onAssetProgress: ((Double?) -> Void)?
    @_spi(Performance) public var onPerformanceSample: (@Sendable (SpeechPerformanceSample) -> Void)?
    public private(set) var retainedTake: RetainedDictation?
    private var audioStore: SpeechAudioStore?
    private var audioLength: Double = 0

    public private(set) var appleErrors: [String: String] = [:]
    public private(set) var batchErrors: [String: String] = [:]
    private var batchEngines: [any BatchTranscriber] = []
    private var chosenLocales: [Locale] = []
    private var forwardingTask: Task<Void, Never>?

    private var processor: SpeechTranscriptProcessor?
    private var modules: [SpeechTranscriber] = []
    private var sessionID = UUID()
    private var publishedRevision = 0
    private var analyzer: SpeechAnalyzer?
    private var contextualStrings: [String] = []
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTasks: [Int: Task<Void, Never>] = [:]
    private var moduleLocales: [Locale] = []

    private let recoveryRoot: URL
    public init(recoveryRoot: URL = RetainedDictation.root) { self.recoveryRoot = recoveryRoot }

    deinit {
        input?.finish()
        forwardingTask?.cancel()
        resultsTasks.values.forEach { $0.cancel() }
        let analyzer = analyzer
        let processor = processor
        let audioStore = audioStore
        Task { await processor?.cancel(); await audioStore?.close(); await analyzer?.cancelAndFinishNow() }
    }

    /// Speech-supported equivalents of `locales`, deduplicated, in order.
    public static func resolve(_ locales: [Locale]) async -> [Locale] {
        let supportedLanguages = Set(await SpeechTranscriber.supportedLocales.map(BatchRouting.languageCode))
        var seen = Set<String>()
        var result: [Locale] = []
        for locale in locales where supportedLanguages.contains(BatchRouting.languageCode(locale)) {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale),
               seen.insert(supported.identifier).inserted {
                result.append(supported)
            }
        }
        return result
    }

    public static var supportedLocales: [Locale] {
        get async { await SpeechTranscriber.supportedLocales }
    }

    /// Makes `locales` the app's reserved speech languages and fetches their models.
    ///
    /// The OS caps each app at `AssetInventory.maximumReservedLocales` (5) reserved
    /// languages and fails analysis beyond that, so languages the user no longer dictates
    /// in are released first.
    public static func setLanguages(_ locales: [Locale], progress: ((Double?) -> Void)? = nil) async throws {
        let supported = await resolve(locales)
        let keep = Set((locales + supported).map(BatchRouting.languageCode))
        for reserved in await AssetInventory.reservedLocales where !keep.contains(BatchRouting.languageCode(reserved)) {
            _ = await AssetInventory.release(reservedLocale: reserved)
        }
        if !supported.isEmpty { try await prepareAssets(locales: locales, progress: progress) }
    }

    /// Downloads speech models the OS doesn't have yet. Call early (e.g. at launch) so the
    /// first dictation doesn't stall on a download.
    public static func prepareAssets(locales: [Locale], progress: ((Double?) -> Void)? = nil) async throws {
        _ = try await makeModules(locales: locales, progress: progress)
    }

    /// Loads the speech models for `locales` into memory ahead of the first utterance, so
    /// `start` doesn't pay for it while the user is already talking. Never downloads:
    /// assets that aren't installed are left for the explicit language flow.
    public static func prewarm(locales: [Locale]) async {
        let supported = await resolve(locales)
        guard !supported.isEmpty else { return }
        let modules = supported.map {
            SpeechTranscriber(locale: $0, transcriptionOptions: [],
                              reportingOptions: [.volatileResults, .fastResults],
                              attributeOptions: [.transcriptionConfidence, .audioTimeRange])
        }
        let status = await AssetInventory.status(forModules: modules)
        let installed = await SpeechTranscriber.installedLocales
        let ready = supported.map {
            SpeechAssetPreparation.isReady(locale: $0, statusBefore: status, statusAfter: status,
                                           installedLocales: installed)
        }
        guard ready.allSatisfy({ $0 }),
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else { return }
        let analyzer = SpeechAnalyzer(modules: modules)
        try? await analyzer.prepareToAnalyze(in: format)
        await analyzer.cancelAndFinishNow()
    }

    /// Starts analysis and returns the audio format the analyzer wants, plus the sink to
    /// push converted buffers into. Buffers must be pushed in capture order.
    ///
    /// - Parameters:
    ///   - locales: candidate languages. One runs at no extra cost; each extra one adds a
    ///     parallel transcriber, so keep the list short.
    ///   - displayLocale: initial language for the live tail, until speech provides evidence to switch.
    public func start(locales: [Locale], displayLocale: Locale? = nil,
                      batchEngines: [any BatchTranscriber] = []) async throws
        -> (AVAudioFormat, AsyncStream<AnalyzerInput>.Continuation)
    {
        text = ""
        volatileText = ""
        batchErrors = [:]
        appleErrors = [:]
        chosenLocales = locales
        self.batchEngines = []
        var seen = Set<String>()
        for engine in batchEngines where !BatchRouting.matching(locales, supportedBy: engine.languages).isEmpty {
            if seen.insert(engine.id).inserted, await engine.isAvailable() { self.batchEngines.append(engine) }
        }
        let appleLocales = await Self.resolve(locales)
        var pairs: [(locale: Locale, module: SpeechTranscriber)] = []
        if self.batchEngines.isEmpty {
            pairs = try await Self.makeModules(locales: locales, progress: onAssetProgress)
        } else {
            // Some OS releases advertise a locale before its asset is distributable.
            // A failed Apple lane must not prevent an installed batch engine from working.
            for locale in appleLocales {
                do { pairs += try await Self.makeModules(locales: [locale], enabledLocales: locales, progress: onAssetProgress) }
                catch {
                    guard self.batchEngines.contains(where: {
                        !BatchRouting.matching([locale], supportedBy: $0.languages).isEmpty
                    }) else { throw error }
                    appleErrors[locale.identifier] = error.localizedDescription
                }
            }
        }
        let modules = pairs.map(\.module)
        let format: AVAudioFormat
        if modules.isEmpty, let rate = self.batchEngines.first?.sampleRate,
           let batchFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                           channels: 1, interleaved: false) {
            format = batchFormat
        } else if let appleFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) {
            format = appleFormat
        } else { throw ScribeError.noAudioFormat }
        let displayIndex = pairs.firstIndex { $0.locale.identifier == displayLocale?.identifier } ?? 0
        let sessionID = UUID()
        self.sessionID = sessionID
        publishedRevision = 0
        self.modules = modules
        moduleLocales = pairs.map(\.locale)
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (forwarded, sink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = modules.isEmpty ? nil : SpeechAnalyzer(modules: modules)
        let take = try RetainedDictation(root: recoveryRoot, languages: locales.map(\.identifier))
        retainedTake = take
        let store = try SpeechAudioStore(url: take.file, format: format, engines: self.batchEngines, retainedSeconds: modules.count > 1 ? 30 : 0,
                                         sink: analyzer == nil ? nil : sink)
        audioStore = store
        audioLength = 0
        let processor = SpeechTranscriptProcessor(locales: moduleLocales, displayIndex: displayIndex,
                                                   measure: onPerformanceSample,
                                                   clip: { try await store.clip(start: $0, end: $1) },
                                                   switchLane: { [weak self] index, generation, start in
            await self?.relock(to: index, generation: generation, from: start, sessionID: sessionID) ?? false
        }, update: { [weak self] snapshot in
            guard let self, self.sessionID == sessionID else { return }
            self.publish(snapshot)
        })
        self.processor = processor
        await processor.setContext(contextualStrings)
        self.analyzer = analyzer
        self.input = input
        resultsTasks = Dictionary(uniqueKeysWithValues: modules.enumerated().map { index, module in
            (index, resultTask(module, index: index, generation: 0, processor: processor, sessionID: sessionID))
        })
        if !contextualStrings.isEmpty, let analyzer { try? await applyContext(to: analyzer) }
        forwardingTask = Task.detached {
            for await packet in stream {
                guard !Task.isCancelled else { break }
                await store.append(packet)
            }
            await store.close()
        }
        try await analyzer?.start(inputSequence: forwarded)
        return (format, input)
    }

    /// May be called before or after start: the window read races analyzer setup.
    /// Context belongs to this utterance and is never shared with the next analyzer.
    public func setContext(contextualStrings: [String]) async throws {
        self.contextualStrings = contextualStrings
        await processor?.setContext(contextualStrings)
        if let analyzer { try await applyContext(to: analyzer) }
    }

    private func applyContext(to analyzer: SpeechAnalyzer) async throws {
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        try await analyzer.setContext(context)
    }

    /// Flushes remaining audio and returns the best transcript and the language it's in.
    public func finish(keepingAudioUntilDelivery: Bool = false) async -> (text: String, locale: Locale?) {
        await processor?.endInput()
        input?.finish()
        input = nil
        await forwardingTask?.value
        audioLength = await audioStore?.duration ?? 0
        if audioLength == 0 { discardRetainedTake() }
        let result = await FinishDeadline.wait(seconds: FinishDeadline.seconds(audioLength: audioLength)) {
            await self.finalize()
        } fallback: {
            if let snapshot = self.processor?.latestSnapshot { self.publish(snapshot) }
            let analyzer = self.analyzer
            self.resultsTasks.values.forEach { $0.cancel() }
            let processor = self.processor
            Task { await processor?.cancel(); await analyzer?.cancelAndFinishNow() }
            return (self.text, Optional<Locale>.none)
        }
        let delivered = result.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !text.isEmpty ? (text, Optional<Locale>.none) : result
        if !keepingAudioUntilDelivery, !delivered.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { discardRetainedTake() }
        return delivered
    }

    /// Delivery owners acknowledge after insertion or a successful durable save.
    public func discardRetainedTake() {
        guard let take = retainedTake else { return }
        do { try take.remove(); retainedTake = nil } catch { /* Keep recovery visible if deletion failed. */ }
    }

    private func finalize() async -> (text: String, locale: Locale?) {
        input?.finish()
        input = nil
        await forwardingTask?.value
        forwardingTask = nil
        while let current = analyzer {
            try? await current.finalizeAndFinishThroughEndOfInput()
            for task in resultsTasks.values { await task.value }
            if analyzer === current { analyzer = nil; break }
        }
        modules = []
        resultsTasks = [:]
        let batchCandidates = await audioStore?.batchCandidates(locales: chosenLocales) ?? []
        batchErrors.merge(await audioStore?.captureErrors ?? [:]) { _, latest in latest }
        guard !Task.isCancelled else { return (text, nil) }
        guard let best = await processor?.finish(batch: batchCandidates) else { return ("", nil) }
        return (best.text, best.locale)
    }

    public func cancel() async {
        sessionID = UUID()
        await processor?.cancel()
        processor = nil
        modules = []
        input?.finish()
        input = nil
        forwardingTask?.cancel()
        await forwardingTask?.value
        forwardingTask = nil
        audioLength = await audioStore?.duration ?? 0
        await audioStore?.discardCache()
        if audioLength == 0 { discardRetainedTake() }
        batchEngines = []
        await analyzer?.cancelAndFinishNow()
        resultsTasks.values.forEach { $0.cancel() }
        analyzer = nil
        resultsTasks = [:]
    }

    private func lockModules(to index: Int, sessionID: UUID) async {
        guard self.sessionID == sessionID, modules.indices.contains(index), let analyzer else { return }
        let start = ContinuousClock.now
        do {
            try await analyzer.setModules([modules[index]])
            guard self.sessionID == sessionID else { return }
            for (other, task) in resultsTasks where other != index { task.cancel() }
            modules = []
            let active = await analyzer.modules.count
            measure("activeLanes_\(active)", since: start, audioEnd: await audioStore?.duration ?? 0)
        } catch {
            // Ignored results cannot delay the HUD if the OS rejects module removal.
            measure("moduleRemovalFailed", since: start, audioEnd: audioLength)
        }
    }

    private func resultTask(_ module: SpeechTranscriber, index: Int, generation: Int,
                            processor: SpeechTranscriptProcessor, sessionID: UUID) -> Task<Void, Never> {
        Task.detached { [weak self] in
            do {
                for try await result in module.results {
                    try Task.checkCancellation()
                    let event = SpeechTranscriptProcessor.Event(text: result.text, isFinal: result.isFinal,
                        start: result.range.start.seconds, end: result.range.end.seconds, index: index, generation: generation)
                    if let locked = await processor.apply(event) { await self?.lockModules(to: locked, sessionID: sessionID) }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await self?.recognitionFailed(error, index: index, sessionID: sessionID)
            }
        }
    }

    private func recognitionFailed(_ error: any Error, index: Int, sessionID: UUID) {
        guard self.sessionID == sessionID, moduleLocales.indices.contains(index) else { return }
        appleErrors[moduleLocales[index].identifier] = error.localizedDescription
        let failure = error as NSError
        measure("resultError_\(failure.domain)_\(failure.code)", since: .now, audioEnd: audioLength)
    }

    private func relock(to index: Int, generation: Int, from start: Double, sessionID: UUID) async -> Bool {
        guard self.sessionID == sessionID, moduleLocales.indices.contains(index), let store = audioStore,
              let processor else { return false }
        let module = SpeechTranscriber(locale: moduleLocales[index], transcriptionOptions: [],
                                       reportingOptions: [.volatileResults, .fastResults],
                                       attributeOptions: [.transcriptionConfidence, .audioTimeRange])
        let replacement = SpeechAnalyzer(modules: [module])
        let (stream, sink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let task = resultTask(module, index: index, generation: generation, processor: processor, sessionID: sessionID)
        do {
            if !contextualStrings.isEmpty { try await applyContext(to: replacement) }
            try await replacement.start(inputSequence: stream)
            guard self.sessionID == sessionID else { throw CancellationError() }
            try await store.replaceSink(sink, from: start)
            let previous = analyzer
            resultsTasks.values.forEach { $0.cancel() }
            resultsTasks = [index: task]
            modules = []
            analyzer = replacement
            Task { await previous?.cancelAndFinishNow() }
            return true
        } catch {
            sink.finish()
            task.cancel()
            await replacement.cancelAndFinishNow()
            return false
        }
    }

    private func publish(_ snapshot: SpeechTranscriptProcessor.Snapshot) {
        guard snapshot.revision > publishedRevision else { return }
        publishedRevision = snapshot.revision
        guard text != snapshot.text || volatileText != snapshot.volatileText else { return }
        let start = ContinuousClock.now
        text = snapshot.text
        volatileText = snapshot.volatileText
        onUpdate?(text)
        measure("publish", since: start, audioEnd: snapshot.audioEnd)
    }

    private func measure(_ phase: String, since start: ContinuousClock.Instant, audioEnd: Double) {
        let elapsed = start.duration(to: .now).components
        onPerformanceSample?(.init(phase: phase, audioEnd: audioEnd,
                                  milliseconds: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
                                  onMainThread: Thread.isMainThread))
    }

    /// Whitespace/punctuation-only runs can lack timing; keep them attached to the
    /// preceding timed token. Missing timing on actual words disables mixing safely.
    nonisolated static func timedTokens(_ text: AttributedString, countWords: Bool = true) -> (tokens: [SpeechToken], complete: Bool) {
        var tokens: [SpeechToken] = []
        var complete = true
        var prefix = ""
        for run in text.runs {
            let value = String(text[run.range].characters)
            if let range = run.audioTimeRange,
               range.start.seconds.isFinite, range.end.seconds.isFinite,
               range.duration.seconds >= 0 {
                tokens.append(.init(text: prefix + value, start: range.start.seconds,
                                    end: range.end.seconds, confidence: run.transcriptionConfidence ?? 0, words: countWords ? nil : 0))
                prefix = ""
            } else if value.unicodeScalars.contains(where: { CharacterSet.letters.union(.decimalDigits).contains($0) }) {
                complete = false
            } else if let last = tokens.popLast() {
                tokens.append(.init(text: last.text + value, start: last.start, end: last.end, confidence: last.confidence, words: countWords ? nil : 0))
            } else { prefix += value }
        }
        return (tokens, complete)
    }

    nonisolated static func join(_ head: String, _ tail: String) -> String {
        var result = head
        append(tail, to: &result)
        return result
    }

    nonisolated static func append(_ tail: String, to head: inout String) {
        let tail = removingSharedPunctuation(tail, after: head)
        if !head.isEmpty, let first = tail.first, !first.isWhitespace,
           !boundaryPunctuation.contains(first), !(head.last?.isWhitespace ?? false) {
            head.append(" ")
        }
        head.append(tail)
    }

    nonisolated private static let boundaryPunctuation = ",.!?;:，。！？、；：)]}'’”\""

    /// Untimed punctuation can belong to the next word in the live lane but the
    /// previous word in a padded replay. Remove only their shared punctuation edge;
    /// repeated words and punctuation inside either fragment remain verbatim.
    nonisolated private static func removingSharedPunctuation(_ tail: String, after head: String) -> String {
        let content = tail.drop(while: \.isWhitespace)
        let leading = Array(content.prefix { boundaryPunctuation.contains($0) })
        guard !leading.isEmpty else { return tail }
        let trailing = Array(head.reversed().drop(while: \.isWhitespace)
            .prefix { boundaryPunctuation.contains($0) }).reversed()
        for count in stride(from: min(leading.count, trailing.count), through: 1, by: -1) {
            let matches = zip(trailing.suffix(count), leading.prefix(count)).allSatisfy { left, right in
                left == right || ("'’".contains(left) && "'’".contains(right))
            }
            if matches {
                let remainder = content.dropFirst(count)
                return String(head.last?.isWhitespace == true ? remainder.drop(while: \.isWhitespace) : remainder)
            }
        }
        return tail
    }

    private static func makeModules(locales: [Locale], enabledLocales: [Locale]? = nil, progress: ((Double?) -> Void)? = nil) async throws -> [(locale: Locale, module: SpeechTranscriber)] {
        let supported = await resolve(locales)
        guard !supported.isEmpty else {
            throw ScribeError.unsupportedLocale(locales.first ?? .current)
        }
        let pairs = supported.map {
            (locale: $0, module: SpeechTranscriber(
                locale: $0,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: [.transcriptionConfidence, .audioTimeRange]
            ))
        }
        for pair in pairs {
            try await SpeechAssetPreparation.prepare(module: pair.module, locale: pair.locale,
                                                     enabledLocales: enabledLocales ?? locales, progress: { progress?($0) })
        }
        return pairs
    }
}
