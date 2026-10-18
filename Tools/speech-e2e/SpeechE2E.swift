import AVFoundation
import Foundation
import Darwin
import NaturalLanguage
import ScribeCore
import Speech
import Synchronization

@main struct SpeechE2E {
    @MainActor static func main() async throws {
        #if os(macOS)
        if CommandLine.arguments.contains("--languages") {
            print("Apple: \(await LiveTranscriber.supportedLocales.map(\.identifier).sorted())")
            print("Parakeet-only: \(await ParakeetTranscriber.appleUnsupportedLanguages.map(\.identifier))")
            return
        }
        if CommandLine.arguments.contains("--bias-matrix") {
            try await BiasMatrix.run(realtime: CommandLine.arguments.contains("--realtime"),
                                     customLanguageModel: CommandLine.arguments.contains("--custom-lm"))
            return
        }
        guard CommandLine.arguments.count >= 3 else {
            print("Usage: speech-e2e clip.aiff en_GB,nl_NL [--parakeet] [--live] [--realtime] [--microphone] [--reference-file text.txt] [--dictionary vocabulary.json] [--assert-live-cadence-ms 300] [--dictation-transcriber] [--no-replacement]")
            print("       speech-e2e --bias-matrix [--realtime] [--custom-lm]"); return
        }
        let url = URL(filePath: CommandLine.arguments[1])
        let locales = CommandLine.arguments[2].split(separator: ",").map { Locale(identifier: String($0)) }
        let store = ModelStore()
        let engines: [any BatchTranscriber] = CommandLine.arguments.contains("--parakeet")
            ? [ParakeetTranscriber(modelDirectory: store.directory(for: ModelCatalog.parakeet))] : []
        var dictionary: [DictionaryEntry] = []
        if let index = CommandLine.arguments.firstIndex(of: "--dictionary"),
           CommandLine.arguments.indices.contains(index + 1) {
            let data = try Data(contentsOf: URL(filePath: CommandLine.arguments[index + 1]))
            let decoder = JSONDecoder()
            if let document = try? decoder.decode(Vocabulary.Document.self, from: data) {
                dictionary = document.dictionary
            } else {
                dictionary = try decoder.decode([DictionaryEntry].self, from: data)
            }
        }
        if CommandLine.arguments.contains("--dictation-transcriber") || CommandLine.arguments.contains("--no-replacement") {
            // Isolate one engine and locale so language selection cannot confound the comparison.
            guard let locale = locales.first else { throw ExperimentError("Supply a locale") }
            let measuresCadence = CommandLine.arguments.contains("--assert-live-cadence-ms")
            let outcome = try await RawRecognition.run(
                clip: url, locale: locale,
                engine: CommandLine.arguments.contains("--dictation-transcriber") ? .dictation : .speech,
                contextualStrings: DictionaryEntry.contextualStrings(in: dictionary),
                realtime: CommandLine.arguments.contains("--realtime") || measuresCadence)
            print("raw=\(outcome.text)")
            if !CommandLine.arguments.contains("--no-replacement") {
                print("replaced=\(DictionaryReplacement.apply(to: outcome.text, dictionary: dictionary))")
            }
            if let index = CommandLine.arguments.firstIndex(of: "--reference-file"),
               CommandLine.arguments.indices.contains(index + 1) {
                let reference = try String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8)
                let score = WordErrorScore(reference: reference, actual: outcome.text)
                print("referenceWords=\(score.words) wordErrors=\(score.errors) wer=\(score.rate)")
            }
            print("firstResult=\(outcome.firstResult ?? -1) firstVolatile=\(outcome.firstVolatile ?? -1) "
                  + "streamingUpdates=\(outcome.streamingUpdates) "
                  + "maximumGrowthGapMs=\((outcome.growthGaps.max() ?? 0) * 1_000)")
            if let index = CommandLine.arguments.firstIndex(of: "--assert-live-cadence-ms"),
               CommandLine.arguments.indices.contains(index + 1),
               let milliseconds = Double(CommandLine.arguments[index + 1]) {
                let gap = outcome.growthGaps.max() ?? .infinity
                print("liveGrowthUpdates=\(outcome.growthGaps.count + (outcome.streamingUpdates > 0 ? 1 : 0)) "
                      + "maximumGrowthGapMs=\(gap * 1_000) targetMs=\(milliseconds)")
                if outcome.growthGaps.isEmpty || gap * 1_000 > milliseconds { Darwin.exit(1) }
            }
            return
        }
        let transcriber = LiveTranscriber()
        try? await transcriber.setContext(contextualStrings: DictionaryEntry.contextualStrings(in: dictionary))
        let start = ContinuousClock.now
        var growthTimes: [TimeInterval] = []
        var maximumCharacters = 0
        let measuresCadence = CommandLine.arguments.contains("--assert-live-cadence-ms")
        let realtime = CommandLine.arguments.contains("--realtime") || measuresCadence
        if CommandLine.arguments.contains("--live") || measuresCadence {
            transcriber.onUpdate = { [weak transcriber] text in
                if text.count > maximumCharacters {
                    maximumCharacters = text.count
                    growthTimes.append(ProcessInfo.processInfo.systemUptime)
                }
                if CommandLine.arguments.contains("--live") {
                    print("live[\(start.duration(to: .now))] characters=\(text.count) volatileCharacters=\(transcriber?.volatileText.count ?? 0)")
                }
            }
        }
        let (format, sink) = try await transcriber.start(locales: locales, batchEngines: engines)
        if CommandLine.arguments.contains("--microphone") {
            guard await Microphone.requestAccess() else { throw ScribeError.microphoneDenied }
            let microphone = Microphone()
            let counts = Mutex((buffers: 0, peak: Float(0)))
            let (captured, captureSink) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let forwarding = Task {
                var converted = 0
                for await input in captured { sink.yield(input); converted += 1 }
                return converted
            }
            try microphone.start(format: format, sink: captureSink,
                                 formatChanged: { print($0) }) { level in
                counts.withLock { $0.buffers += 1; $0.peak = max($0.peak, level) }
            }
            // Acoustic loopback exercises the microphone input; file conversion alone cannot.
            let clip = try AVAudioFile(forReading: url)
            let duration = Double(clip.length) / clip.processingFormat.sampleRate
            let playback = Process()
            playback.executableURL = URL(filePath: "/usr/bin/afplay")
            playback.arguments = [url.path]
            defer { if playback.isRunning { playback.terminate() } }
            try await Task.sleep(for: .milliseconds(500))
            try playback.run()
            try await Task.sleep(for: .seconds(duration + 1))
            microphone.stop()
            captureSink.finish()
            let converted = await forwarding.value
            let stats = counts.withLock { $0 }
            print("microphoneBuffers=\(stats.buffers) converted=\(converted) peak=\(stats.peak) duration=\(duration)")
        } else {
            let file = try AVAudioFile(forReading: url)
            guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw ScribeError.noAudioFormat }
            let feeder = AudioFileFeeder(file)
            while true {
                // Match microphone packet cadence; a 4096-frame file packet can
                // itself consume nearly the entire live-preview latency budget.
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
                    if realtime {
                        try await Task.sleep(for: .seconds(Double(buffer.frameLength) / format.sampleRate))
                    }
                }
                if status == .endOfStream { break }
                if status == .error { throw ScribeError.noAudioFormat }
            }
        }
        let streamingTimes = growthTimes
        let result = await transcriber.finish()
        var cadenceFailed = false
        if let index = CommandLine.arguments.firstIndex(of: "--assert-live-cadence-ms"),
           CommandLine.arguments.indices.contains(index + 1),
           let milliseconds = Double(CommandLine.arguments[index + 1]) {
            let gap = zip(streamingTimes, streamingTimes.dropFirst()).map { $1 - $0 }.max() ?? .infinity
            print("liveGrowthUpdates=\(streamingTimes.count) maximumGrowthGapMs=\(gap * 1_000) targetMs=\(milliseconds)")
            cadenceFailed = streamingTimes.count < 2 || gap * 1_000 > milliseconds
        }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = result.text
        print("finalWords=\(tokenizer.tokens(for: result.text.startIndex..<result.text.endIndex).count)")
        if CommandLine.arguments.contains("--microphone") {
            // Captured room speech is never logged; compare a known fixture using counts only.
            print("locale=\(result.locale?.identifier ?? "none") characters=\(result.text.count)")
            if let index = CommandLine.arguments.firstIndex(of: "--reference-file"),
               CommandLine.arguments.indices.contains(index + 1) {
                let reference = try String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8)
                let score = WordErrorScore(reference: reference, actual: result.text)
                print("referenceWords=\(score.words) wordErrors=\(score.errors) wer=\(score.rate)")
            }
        } else {
            print("locale=\(result.locale?.identifier ?? "none") characters=\(result.text.count)")
            if !dictionary.isEmpty { print("cleanedCharacters=\(TextCleanup.clean(result.text, dictionary: dictionary).count)") }
        }
        print("elapsed=\(start.duration(to: .now)) batchErrors=\(transcriber.batchErrors) appleErrors=\(transcriber.appleErrors)")
        print("Parakeet-only languages=\(await ParakeetTranscriber.appleUnsupportedLanguages.map(\.identifier).joined(separator: ","))")
        if cadenceFailed { Darwin.exit(1) }
        #endif
    }
}

/// AVAudioConverter calls the feeder synchronously on its caller's thread.
final class AudioFileFeeder: @unchecked Sendable {
    let file: AVAudioFile
    var error: Error?
    init(_ file: AVAudioFile) { self.file = file }
    func next(_ requested: AVAudioPacketCount, state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard file.framePosition < file.length else { state.pointee = .endOfStream; return nil }
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: requested)!
        do { try file.read(into: input); state.pointee = .haveData; return input }
        catch { self.error = error; state.pointee = .endOfStream; return nil }
    }
}

/// Fixture scoring normalizes case, punctuation and whole-hour numerals; no content is logged.
struct WordErrorScore {
    let words: Int
    let errors: Int
    var rate: Double { words == 0 ? 0 : Double(errors) / Double(words) }

    init(reference: String, actual: String) {
        let expected = Self.tokens(reference)
        let heard = Self.tokens(actual)
        words = expected.count
        var row = Array(0...heard.count)
        for (index, word) in expected.enumerated() {
            var next = [index + 1]
            for (other, candidate) in heard.enumerated() {
                next.append(min(next[other] + 1, row[other + 1] + 1, row[other] + (word == candidate ? 0 : 1)))
            }
            row = next
        }
        errors = row.last ?? words
    }

    static func tokens(_ text: String) -> [String] {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.numberStyle = .spellOut
        return text.lowercased().replacingOccurrences(of: #"(\d+):00\b"#, with: "$1", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).map { word in
                let token = word.filter { $0.isLetter || $0.isNumber }
                if let number = Int(token) { return formatter.string(from: NSNumber(value: number)) ?? token }
                return token
            }.filter { !$0.isEmpty }
    }
}
