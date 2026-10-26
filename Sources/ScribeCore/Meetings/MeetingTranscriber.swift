import AVFoundation
import Foundation
import Speech

/// Long-form, independent analyzers per recording stream, with assets prepared before analysis.
public enum MeetingTranscriber {
    public static func validate(locale: Locale, enabledLocales: [Locale]? = nil,
                                progress: (@MainActor (Double?) -> Void)? = nil) async throws {
        _ = try await makeModule(locale: locale, enabledLocales: enabledLocales, progress: progress)
    }

    /// Apple's recognizer is preferred; Parakeet only serves languages Apple doesn't offer at
    /// all, routed exactly as dictation's pack languages are.
    public static func needsParakeet(_ locale: Locale) async -> Bool {
        let packOnly = BatchRouting.batchOnly([locale], appleLocales: await SpeechTranscriber.supportedLocales)
        return !BatchRouting.matching(packOnly, supportedBy: ParakeetTranscriber.supportedLanguages).isEmpty
    }

    private static func makeModule(locale: Locale, enabledLocales: [Locale]?,
                                   progress: (@MainActor (Double?) -> Void)? = nil) async throws -> SpeechTranscriber {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw ScribeError.unsupportedLocale(locale)
        }
        let module = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                       reportingOptions: [], attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        try await SpeechAssetPreparation.prepare(module: module, locale: supported,
                                                 enabledLocales: enabledLocales, progress: progress)
        return module
    }

    /// `enabledLocales` protects current preferences when replaying recordings made with older languages.
    /// Leave it nil when unknown; preparation then preserves all existing reservations.
    public static func transcribe(file url: URL, locale: Locale, speakerID: String,
                                  offset: Double = 0, parakeet: ParakeetTranscriber? = nil, enabledLocales: [Locale]? = nil,
                                  progress: @escaping @Sendable (Double) async -> Void = { _ in }) async throws -> [MeetingTurn] {
        if let parakeet, await needsParakeet(locale) {
            return try await parakeet.transcribe(file: url).map {
                .init(speakerID: speakerID, start: offset + $0.start, end: offset + $0.end, text: $0.text)
            }
        }
        return try await transcribe(file: url, locale: locale, speakerID: speakerID, offset: offset, seconds: nil, enabledLocales: enabledLocales, progress: progress).turns
    }

    /// A short stretch from the start of a file, with the recognizer's confidence, to choose a language.
    public static func probe(file url: URL, locale: Locale, seconds: Double, enabledLocales: [Locale]? = nil) async throws -> LanguagePicker.Candidate {
        let result = try await transcribe(file: url, locale: locale, speakerID: "probe", offset: 0, seconds: seconds, enabledLocales: enabledLocales)
        let text = result.turns.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(locale: locale, text: text, confidence: result.confidence)
    }

    private static func transcribe(file url: URL, locale: Locale, speakerID: String, offset: Double,
                                   seconds: Double?, enabledLocales: [Locale]?, progress: @escaping @Sendable (Double) async -> Void = { _ in }) async throws -> (turns: [MeetingTurn], confidence: Double) {
        let module = try await makeModule(locale: locale, enabledLocales: enabledLocales)
        let analyzer = SpeechAnalyzer(modules: [module])
        let duration = max(0.001, seconds ?? MeetingAudioFiles.duration(of: url) ?? 0.001)
        let results = Task<([MeetingTurn], Double), Error> {
            var turns: [MeetingTurn] = []
            var confidences: [Double] = []
            for try await result in module.results where result.isFinal {
                var pieces: [MeetingTurn] = []
                var prefix = ""
                for run in result.text.runs {
                    let text = String(result.text[run.range].characters)
                    if let confidence = run.transcriptionConfidence { confidences.append(confidence) }
                    if let time = run.audioTimeRange {
                        pieces.append(.init(speakerID: speakerID, start: offset + time.start.seconds,
                                            end: offset + time.end.seconds, text: prefix + text))
                        prefix = ""
                    } else if !pieces.isEmpty {
                        // Punctuation/whitespace can be un-timed. Keep it with the preceding words.
                        pieces[pieces.count - 1].text += text
                    } else { prefix += text }
                }
                if pieces.isEmpty {
                    pieces.append(.init(speakerID: speakerID, start: offset + result.range.start.seconds,
                                        end: offset + result.range.end.seconds, text: String(result.text.characters)))
                }
                turns += pieces
                await progress(min(1, max(0, result.range.end.seconds / duration)))
            }
            let confidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
            return (turns, confidence)
        }
        do {
            // A trimmed copy keeps the probe on the same file path as full transcription; the
            // analyzer converts file audio itself, which it does not do for pushed buffers.
            let source = try seconds.map { try trimmed(url, seconds: $0) } ?? url
            defer { if source != url { try? FileManager.default.removeItem(at: source) } }
            let file = try AVAudioFile(forReading: source)
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            return try await withTaskCancellationHandler { try await results.value } onCancel: {
                results.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private static func trimmed(_ url: URL, seconds: Double) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let output = FileManager.default.temporaryDirectory.appending(path: "scribe-probe-\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: output, settings: input.fileFormat.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        var remaining = min(input.length, AVAudioFramePosition(seconds * format.sampleRate))
        while remaining > 0 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { break }
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, remaining)))
            guard buffer.frameLength > 0 else { break }
            try file.write(from: buffer)
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
        return output
    }
}

/// Chooses the spoken language among the user's dictation languages, as dictation does:
/// every candidate hears the same opening stretch and `LanguagePicker` weighs confidence
/// against how strongly each transcript reads as its own language.
public enum MeetingLanguage {
    public static let probeSeconds = 30.0

    /// - Parameter files: streams in preference order; the first with any speech decides.
    public static func detect(files: [URL], among locales: [Locale], parakeet: ParakeetTranscriber?,
                              seconds: Double = probeSeconds, enabledLocales: [Locale]? = nil) async -> Locale {
        guard let first = locales.first else { return .current }
        guard locales.count > 1 else { return first }
        var apple: [Locale] = [], pack: [Locale] = []
        for locale in locales {
            if await MeetingTranscriber.needsParakeet(locale) { pack.append(locale) } else { apple.append(locale) }
        }
        for file in files {
            var candidates: [LanguagePicker.Candidate] = []
            for locale in apple {
                if let candidate = try? await MeetingTranscriber.probe(file: file, locale: locale, seconds: seconds, enabledLocales: enabledLocales.map { $0 + locales }) {
                    candidates.append(candidate)
                }
            }
            if let parakeet, !pack.isEmpty, let candidate = try? await parakeet.probe(file: file, among: pack, seconds: seconds) {
                candidates.append(candidate)
            }
            if let best = LanguagePicker.best(of: candidates), !best.text.isEmpty { return best.locale }
        }
        return first
    }
}
