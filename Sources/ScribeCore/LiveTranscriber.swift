import AVFoundation
import CoreMedia
import Foundation
import Speech

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
/// users one transcriber per language runs on the same audio and timed windows select the
/// best stretches (`LanguagePicker` is the fallback without timing). Create one per utterance: `start()`, push audio into the returned
/// continuation, then `finish()`.
@MainActor
public final class LiveTranscriber {
    /// Live text from the selected languages (finalized plus the still-revising tail).
    public private(set) var text = ""
    /// The suffix that can still be revised, so previews can distinguish it from committed words.
    public private(set) var volatileText = ""
    public var onUpdate: ((String) -> Void)?
    public var onAssetProgress: ((Double?) -> Void)?
    public private(set) var retainedTake: RetainedDictation?
    private var audioFile: AVAudioFile?
    private var audioLength: Double = 0

    public private(set) var appleErrors: [String: String] = [:]
    public private(set) var batchErrors: [String: String] = [:]
    private var batchEngines: [any BatchTranscriber] = []
    private var chosenLocales: [Locale] = []
    private var batchBuffers: [String: BatchAudioBuffer] = [:]
    private var forwardingTask: Task<Void, Never>?

    private var lanes: [SpeechLane] = []
    private var mixedTranscript = MixedLanguageTranscript()
    private var displayIndex = 0
    private var analyzer: SpeechAnalyzer?
    private var contextualStrings: [String] = []
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTasks: [Task<Void, Never>] = []

    private let recoveryRoot: URL
    public init(recoveryRoot: URL = RetainedDictation.root) { self.recoveryRoot = recoveryRoot }

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
        let keep = Set(await resolve(locales).map(\.identifier))
        for reserved in await AssetInventory.reservedLocales where !keep.contains(reserved.identifier) {
            _ = await AssetInventory.release(reservedLocale: reserved)
        }
        if !keep.isEmpty { try await prepareAssets(locales: locales, progress: progress) }
    }

    /// Downloads speech models the OS doesn't have yet. Call early (e.g. at launch) so the
    /// first dictation doesn't stall on a download.
    public static func prepareAssets(locales: [Locale], progress: ((Double?) -> Void)? = nil) async throws {
        _ = try await makeModules(locales: locales, progress: progress)
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
        batchBuffers = [:]
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
                do { pairs += try await Self.makeModules(locales: [locale], progress: onAssetProgress) }
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
        for engine in self.batchEngines {
            batchBuffers[engine.id] = try BatchAudioBuffer(inputFormat: format, sampleRate: engine.sampleRate)
        }

        lanes = pairs.map { SpeechLane(locale: $0.locale) }
        displayIndex = lanes.firstIndex { $0.locale.identifier == displayLocale?.identifier } ?? 0
        mixedTranscript = MixedLanguageTranscript(displayIndex: displayIndex)

        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = modules.isEmpty ? nil : SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        self.input = input

        resultsTasks = modules.enumerated().map { index, module in
            Task { [weak self] in
                do {
                    for try await result in module.results {
                        self?.apply(result, to: index)
                    }
                } catch {
                    // The analyzer ending early just means we keep whatever text we have.
                }
            }
        }

        if !contextualStrings.isEmpty, let analyzer { try? await applyContext(to: analyzer) }
        let take = try RetainedDictation(root: recoveryRoot, languages: locales.map(\.identifier))
        retainedTake = take
        audioFile = try AVAudioFile(forWriting: take.file, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        audioLength = 0
        let (forwarded, sink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        forwardingTask = Task { [weak self] in
            for await packet in stream {
                guard !Task.isCancelled, let self else { break }
                do { try self.audioFile?.write(from: packet.buffer) }
                catch { self.batchErrors["recovery"] = "Couldn't save the recording." }
                self.audioLength += Double(packet.buffer.frameLength) / packet.buffer.format.sampleRate
                for engine in self.batchEngines where self.batchErrors[engine.id] == nil {
                    do { try self.batchBuffers[engine.id]?.append(packet.buffer) }
                    catch { self.batchErrors[engine.id] = error.localizedDescription }
                }
                if analyzer != nil { sink.yield(packet) }
            }
            self?.audioFile = nil
            sink.finish()
        }
        try await analyzer?.start(inputSequence: forwarded)
        return (format, input)
    }

    /// May be called before or after start: the window read races analyzer setup.
    /// Context belongs to this utterance and is never shared with the next analyzer.
    public func setContext(contextualStrings: [String]) async throws {
        self.contextualStrings = contextualStrings
        if let analyzer { try await applyContext(to: analyzer) }
    }

    private func applyContext(to analyzer: SpeechAnalyzer) async throws {
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        try await analyzer.setContext(context)
    }

    /// Flushes remaining audio and returns the best transcript and the language it's in.
    public func finish(keepingAudioUntilDelivery: Bool = false) async -> (text: String, locale: Locale?) {
        input?.finish()
        input = nil
        await forwardingTask?.value
        audioFile = nil
        if audioLength == 0 { discardRetainedTake() }
        let result = await FinishDeadline.wait(seconds: FinishDeadline.seconds(audioLength: audioLength)) {
            await self.finalize()
        } fallback: {
            let analyzer = self.analyzer
            self.resultsTasks.forEach { $0.cancel() }
            Task { await analyzer?.cancelAndFinishNow() }
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
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        for task in resultsTasks { await task.value }
        analyzer = nil
        resultsTasks = []

        var batchCandidates: [LanguagePicker.Candidate] = []
        for engine in batchEngines where batchErrors[engine.id] == nil {
            do {
                guard let buffer = batchBuffers[engine.id] else { continue }
                try buffer.finish()
                let result = try await engine.transcribe(samples: buffer.samples, sampleRate: engine.sampleRate)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let locale = BatchRouting.detectedLocale(
                    for: text, among: BatchRouting.matching(chosenLocales, supportedBy: engine.languages)
                ) {
                    batchCandidates.append(.init(locale: locale, text: text, confidence: result.confidence ?? 0.5))
                }
            } catch { batchErrors[engine.id] = error.localizedDescription }
        }
        batchBuffers = [:]
        guard !Task.isCancelled else { return (text, nil) }
        guard let best = MixedLanguageTranscript.finalSelection(lanes: lanes, batch: batchCandidates) else {
            return ("", nil)
        }
        return (best.text, best.locale)
    }

    public func cancel() async {
        input?.finish()
        input = nil
        forwardingTask?.cancel()
        await forwardingTask?.value
        forwardingTask = nil
        audioFile = nil
        if audioLength == 0 { discardRetainedTake() }
        batchBuffers = [:]
        batchEngines = []
        await analyzer?.cancelAndFinishNow()
        resultsTasks.forEach { $0.cancel() }
        analyzer = nil
        resultsTasks = []
    }

    private func apply(_ result: SpeechTranscriber.Result, to index: Int) {
        lanes[index].apply(result.text, isFinal: result.isFinal)
        if lanes.count == 1 {
            text = lanes[index].text
            volatileText = lanes[index].volatile
        } else {
            text = mixedTranscript.select(lanes, live: true)?.text ?? lanes[displayIndex].text
            volatileText = mixedTranscript.volatileText
        }
        onUpdate?(text)
    }

    /// Whitespace/punctuation-only runs can lack timing; keep them attached to the
    /// preceding timed token. Missing timing on actual words disables mixing safely.
    nonisolated static func timedTokens(_ text: AttributedString) -> (tokens: [SpeechToken], complete: Bool) {
        var tokens: [SpeechToken] = []
        var complete = true
        var prefix = ""
        for run in text.runs {
            let value = String(text[run.range].characters)
            if let range = run.audioTimeRange,
               range.start.seconds.isFinite, range.end.seconds.isFinite,
               range.duration.seconds >= 0 {
                tokens.append(.init(text: prefix + value, start: range.start.seconds,
                                    end: range.end.seconds, confidence: run.transcriptionConfidence ?? 0))
                prefix = ""
            } else if value.unicodeScalars.contains(where: { CharacterSet.letters.union(.decimalDigits).contains($0) }) {
                complete = false
            } else if let last = tokens.popLast() {
                tokens.append(.init(text: last.text + value, start: last.start, end: last.end, confidence: last.confidence))
            } else { prefix += value }
        }
        return (tokens, complete)
    }

    nonisolated static func join(_ head: String, _ tail: String) -> String {
        guard !head.isEmpty, let first = tail.first, !first.isWhitespace, !(head.last?.isWhitespace ?? false) else {
            return head + tail
        }
        return head + " " + tail
    }

    private static func makeModules(locales: [Locale], progress: ((Double?) -> Void)? = nil) async throws -> [(locale: Locale, module: SpeechTranscriber)] {
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
        let modules = pairs.map(\.module)
        if await AssetInventory.status(forModules: modules) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            progress?(0)
            let observer = Task {
                while !Task.isCancelled {
                    progress?(request.progress.fractionCompleted)
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
            }
            defer { observer.cancel(); progress?(nil) }
            try await request.downloadAndInstall()
        }
        return pairs
    }
}
