import AVFoundation
import Foundation
import Speech
import ScribeCore

/// M9.0: does the Dictionary bias *recognition*, or does `DictionaryReplacement` do all the work?
///
/// Runs one analyzer with one module and nothing else: no `LiveTranscriber`, no language
/// picking, no `TextCleanup`. The transcriber type, contextual strings and an optional custom
/// language model are the only variables, so differences are raw recognition.
@MainActor
final class RawRecognition {
    enum Engine: String, CaseIterable {
        case speech = "SpeechTranscriber"
        case dictation = "DictationTranscriber"
    }

    struct Outcome {
        var text: String
        /// Seconds from the first audio packet to the first result of any kind.
        var firstResult: TimeInterval?
        /// First non-final result while audio was still streaming, excluding end-of-input flush.
        var firstVolatile: TimeInterval?
        var streamingUpdates: Int
        /// Seconds between consecutive results, volatile or final.
        var updateGaps: [TimeInterval]
        /// Seconds between results that made the visible text longer (what `--assert-live-cadence-ms` measures).
        var growthGaps: [TimeInterval]
    }

    private var finalized = ""
    private var volatile = ""
    private var resultTimes: [TimeInterval] = []
    private var growthTimes: [TimeInterval] = []
    private var firstVolatileTime: TimeInterval?
    private var longest = 0

    /// - Parameter realtime: pace 30 ms packets like the microphone; needed for cadence, not accuracy.
    static func run(clip: URL, locale: Locale, engine: Engine, contextualStrings: [String],
                    languageModel: SFSpeechLanguageModel.Configuration? = nil,
                    realtime: Bool) async throws -> Outcome {
        let recognition = RawRecognition()
        let module: any SpeechModule
        let results: Task<Void, Error>
        switch engine {
        case .speech:
            guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw ExperimentError("SpeechTranscriber doesn't support \(locale.identifier)")
            }
            // Same options as LiveTranscriber.makeModules, so the baseline is the shipping one.
            let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                                reportingOptions: [.volatileResults, .fastResults],
                                                attributeOptions: [.transcriptionConfidence, .audioTimeRange])
            module = transcriber
            results = Task {
                for try await result in transcriber.results {
                    recognition.apply(String(result.text.characters), isFinal: result.isFinal)
                }
            }
        case .dictation:
            guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else {
                throw ExperimentError("DictationTranscriber doesn't support \(locale.identifier)")
            }
            var preset = DictationTranscriber.Preset.progressiveShortDictation
            if let languageModel { preset.contentHints.insert(.customizedLanguage(modelConfiguration: languageModel)) }
            let transcriber = DictationTranscriber(locale: supported, preset: preset)
            module = transcriber
            results = Task {
                for try await result in transcriber.results {
                    recognition.apply(String(result.text.characters), isFinal: result.isFinal)
                }
            }
        }
        defer { results.cancel() }
        if await AssetInventory.status(forModules: [module]) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw ScribeError.noAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        if !contextualStrings.isEmpty {
            // Set before start, like LiveTranscriber does when the window read wins the race.
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try await analyzer.setContext(context)
        }
        let (stream, sink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        defer { sink.finish() }
        try await analyzer.start(inputSequence: stream)

        let file = try AVAudioFile(forReading: clip)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw ScribeError.noAudioFormat }
        let feeder = AudioFileFeeder(file)
        let start = ProcessInfo.processInfo.systemUptime
        while true {
            let capacity = realtime ? AVAudioFrameCount(format.sampleRate * 0.03) : 4096
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { requested, state in
                feeder.next(requested, state: state)
            }
            if let error { throw error }
            if let error = feeder.error { throw error }
            if buffer.frameLength > 0 {
                sink.yield(AnalyzerInput(buffer: buffer))
                if realtime { try await Task.sleep(for: .seconds(Double(buffer.frameLength) / format.sampleRate)) }
            }
            if status == .endOfStream { break }
            if status == .error { throw ScribeError.noAudioFormat }
        }
        // Cadence describes speech in progress; the flush after end of input is not live preview.
        let streamingResults = recognition.resultTimes
        let streamingGrowth = recognition.growthTimes
        let firstVolatile = recognition.firstVolatileTime.map { $0 - start }
        sink.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await results.value
        let gaps = { (times: [TimeInterval]) in zip(times, times.dropFirst()).map { $1 - $0 } }
        return Outcome(text: Self.join(recognition.finalized, recognition.volatile).trimmingCharacters(in: .whitespacesAndNewlines),
                       firstResult: recognition.resultTimes.first.map { $0 - start },
                       firstVolatile: firstVolatile, streamingUpdates: streamingResults.count,
                       updateGaps: gaps(streamingResults), growthGaps: gaps(streamingGrowth))
    }

    private func apply(_ text: String, isFinal: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        resultTimes.append(now)
        if !isFinal, firstVolatileTime == nil { firstVolatileTime = now }
        if isFinal { finalized = Self.join(finalized, text); volatile = "" } else { volatile = text }
        let visible = finalized.count + volatile.count
        if visible > longest { longest = visible; growthTimes.append(now) }
    }

    // Separate finalized segments may omit their boundary space, just as in LiveTranscriber.
    private static func join(_ head: String, _ tail: String) -> String {
        guard !head.isEmpty, let first = tail.first, !first.isWhitespace,
              !(head.last?.isWhitespace ?? false) else { return head + tail }
        return head + " " + tail
    }

    /// Phrase counts for the Dictionary terms, compiled for `DictationTranscriber`'s
    /// customized-language hint. Returns the configuration and the preparation time.
    static func prepareLanguageModel(locale: Locale, terms: [String], directory: URL) async throws
        -> (SFSpeechLanguageModel.Configuration, TimeInterval) {
        let data = SFCustomLanguageModelData(locale: locale, identifier: "ai.nanth.scribe.m90", version: "1.0")
        for term in terms { data.insert(phraseCount: .init(phrase: term, count: 100)) }
        let training = directory.appending(path: "training-\(locale.identifier).bin")
        try await data.export(to: training)
        let configuration = SFSpeechLanguageModel.Configuration(
            languageModel: directory.appending(path: "lm-\(locale.identifier)"),
            vocabulary: directory.appending(path: "vocab-\(locale.identifier)"))
        let started = ProcessInfo.processInfo.systemUptime
        try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: training, configuration: configuration)
        return (configuration, ProcessInfo.processInfo.systemUptime - started)
    }
}

struct ExperimentError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// The M9.0 test set: TTS sentences carrying rare names and terms, run through
/// {SpeechTranscriber, DictationTranscriber} × {no context, Dictionary as contextual strings}.
@MainActor
enum BiasMatrix {
    struct Case {
        let locale: String
        let voice: String
        let sentence: String
        let terms: [String]
    }

    struct Setup: Hashable {
        let engine: RawRecognition.Engine
        let context: Bool
        let languageModel: Bool
        var name: String {
            engine.rawValue + (context ? " + context" : "") + (languageModel ? " + custom LM" : "")
        }
    }

    /// What a user would have in their Dictionary; also the contextual strings.
    static let dictionary = ["Rinaldi", "NanthAi", "Kubernetes", "Alessandro", "Zanichelli", "Brembate",
                             "Gemma", "Tailscale", "Supabase", "Ravasio", "Ollama"]

    static let cases: [Case] = [
        .init(locale: "en_US", voice: "Samantha", sentence: "Please forward the contract to Alessandro Rinaldi before noon.", terms: ["Alessandro", "Rinaldi"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "NanthAi Scribe now runs entirely on the device.", terms: ["NanthAi"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "We moved the staging cluster to Kubernetes last week.", terms: ["Kubernetes"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "The Zanichelli dictionary is on the second shelf.", terms: ["Zanichelli"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "Our new office is just outside Brembate, near Bergamo.", terms: ["Brembate"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "Gemma handles the rewriting step on the laptop.", terms: ["Gemma"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "Connect to the build machine over Tailscale first.", terms: ["Tailscale"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "The sync backend might move to Supabase next year.", terms: ["Supabase"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "Ask Ravasio whether the invoices were approved.", terms: ["Ravasio"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "You can run the small model locally with Ollama.", terms: ["Ollama"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "Rinaldi said the Kubernetes upgrade went smoothly.", terms: ["Rinaldi", "Kubernetes"]),
        .init(locale: "en_US", voice: "Samantha", sentence: "Alessandro tested NanthAi with Gemma on the train.", terms: ["Alessandro", "NanthAi", "Gemma"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Per favore inoltra il contratto ad Alessandro Rinaldi entro mezzogiorno.", terms: ["Alessandro", "Rinaldi"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "NanthAi Scribe adesso funziona interamente sul dispositivo.", terms: ["NanthAi"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "La settimana scorsa abbiamo spostato il cluster su Kubernetes.", terms: ["Kubernetes"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Il dizionario Zanichelli è sul secondo scaffale.", terms: ["Zanichelli"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Il nuovo ufficio è appena fuori Brembate, vicino a Bergamo.", terms: ["Brembate"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Gemma si occupa della riscrittura sul portatile.", terms: ["Gemma"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Prima collegati alla macchina di build con Tailscale.", terms: ["Tailscale"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Il backend di sincronizzazione potrebbe passare a Supabase.", terms: ["Supabase"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Chiedi a Ravasio se le fatture sono state approvate.", terms: ["Ravasio"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Puoi eseguire il modello piccolo in locale con Ollama.", terms: ["Ollama"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Rinaldi ha detto che l'aggiornamento di Kubernetes è andato bene.", terms: ["Rinaldi", "Kubernetes"]),
        .init(locale: "it_IT", voice: "Alice", sentence: "Alessandro ha provato NanthAi con Gemma sul treno.", terms: ["Alessandro", "NanthAi", "Gemma"]),
    ]

    private struct Tally {
        var hits = 0, terms = 0, errors = 0, words = 0
        var firstVolatiles: [TimeInterval] = []
        var clips = 0, clipsWithVolatile = 0
        var updateGaps: [TimeInterval] = []
        var maxGrowthGaps: [TimeInterval] = []
    }

    /// Synthesizes every clip with `say`, runs all setups, prints per-clip lines and a
    /// Markdown summary, then deletes the clips (and any compiled language models).
    static func run(realtime: Bool, customLanguageModel: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "scribe-m90-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var setups = RawRecognition.Engine.allCases.flatMap { engine in
            [false, true].map { Setup(engine: engine, context: $0, languageModel: false) }
        }
        var models: [String: SFSpeechLanguageModel.Configuration] = [:]
        if customLanguageModel {
            setups.append(Setup(engine: .dictation, context: false, languageModel: true))
            for locale in Set(cases.map(\.locale)).sorted() {
                do {
                    let (configuration, seconds) = try await RawRecognition.prepareLanguageModel(
                        locale: Locale(identifier: locale), terms: dictionary, directory: directory)
                    models[locale] = configuration
                    print("customLM[\(locale)] prepared in \(String(format: "%.2f", seconds)) s")
                } catch {
                    print("customLM[\(locale)] failed: \(error.localizedDescription)")
                }
            }
        }

        var tallies: [String: [Setup: Tally]] = [:]
        for (index, test) in cases.enumerated() {
            let clip = directory.appending(path: "clip-\(index).aiff")
            let say = Process()
            say.executableURL = URL(filePath: "/usr/bin/say")
            say.arguments = ["-v", test.voice, "-o", clip.path, test.sentence]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else { throw ExperimentError("say failed for \(test.voice)") }
            for setup in setups {
                let model = setup.languageModel ? models[test.locale] : nil
                if setup.languageModel && model == nil { continue }
                let outcome = try await RawRecognition.run(
                    clip: clip, locale: Locale(identifier: test.locale), engine: setup.engine,
                    contextualStrings: setup.context ? dictionary : [], languageModel: model, realtime: realtime)
                let heard = " " + WordErrorScore.tokens(outcome.text).joined(separator: " ") + " "
                let hits = test.terms.filter {
                    heard.contains(" " + WordErrorScore.tokens($0).joined(separator: " ") + " ")
                }.count
                let score = WordErrorScore(reference: test.sentence, actual: outcome.text)
                var tally = tallies[test.locale, default: [:]][setup, default: Tally()]
                tally.hits += hits
                tally.terms += test.terms.count
                tally.errors += score.errors
                tally.words += score.words
                tally.clips += 1
                if let first = outcome.firstVolatile {
                    tally.firstVolatiles.append(first)
                    tally.clipsWithVolatile += 1
                }
                tally.updateGaps += outcome.updateGaps
                if let gap = outcome.growthGaps.max() { tally.maxGrowthGaps.append(gap) }
                tallies[test.locale, default: [:]][setup] = tally
                print("[\(test.locale) #\(index)] \(setup.name): terms=\(hits)/\(test.terms.count) "
                      + "errors=\(score.errors)/\(score.words) firstVolatile=\(milliseconds(outcome.firstVolatile)) "
                      + "streamingUpdates=\(outcome.streamingUpdates) "
                      + "maxGrowthGap=\(milliseconds(outcome.growthGaps.max())) | \(outcome.text)")
            }
        }

        print("\n| Lang | Setup | Term hits | WER |" + (realtime ? " First volatile (median) | Update interval (median) | Max growth gap (median per clip) | Volatile clips |" : ""))
        print("|---|---|---:|---:|" + (realtime ? "---:|---:|---:|---:|" : ""))
        for locale in tallies.keys.sorted() {
            for setup in setups {
                guard let tally = tallies[locale]?[setup] else { continue }
                var row = "| \(locale) | \(setup.name) | \(tally.hits)/\(tally.terms) | "
                    + String(format: "%.1f%%", 100 * Double(tally.errors) / Double(max(tally.words, 1))) + " |"
                if realtime {
                    row += " \(milliseconds(median(tally.firstVolatiles))) | \(milliseconds(median(tally.updateGaps))) | \(milliseconds(median(tally.maxGrowthGaps))) | \(tally.clipsWithVolatile)/\(tally.clips) |"
                }
                print(row)
            }
        }
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func milliseconds(_ value: TimeInterval?) -> String {
        value.map { "\(Int(($0 * 1_000).rounded())) ms" } ?? "n/a"
    }
}
