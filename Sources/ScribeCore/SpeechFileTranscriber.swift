import AVFoundation
import Foundation
import Speech

/// A sentence retry receives only its extracted audio span.
/// Assets were prepared for these locales at start; replay never downloads a model.
enum SpeechFileTranscriber {
    static func transcribe(file: URL, locale: Locale, contextualStrings: [String],
                           measure: (@Sendable (SpeechPerformanceSample) -> Void)? = nil) async throws -> SpeechLane {
        let setup = ContinuousClock.now
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                       attributeOptions: [.transcriptionConfidence, .audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [module])
        let results = Task.detached {
            var lane = SpeechLane(locale: locale)
            for try await result in module.results where result.isFinal {
                try Task.checkCancellation()
                lane.apply(result.text, isFinal: true)
            }
            return lane
        }
        return try await withTaskCancellationHandler {
            do {
                if !contextualStrings.isEmpty {
                    let context = AnalysisContext()
                    context.contextualStrings[.general] = contextualStrings
                    try await analyzer.setContext(context)
                }
                try Task.checkCancellation()
                let audio = try AVAudioFile(forReading: file)
                try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
                let elapsed = setup.duration(to: .now).components
                measure?(.init(phase: "spanSetup", audioEnd: Double(audio.length) / audio.processingFormat.sampleRate,
                               milliseconds: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
                               onMainThread: currentThreadIsMain()))
                return try await results.value
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            results.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
    private static func currentThreadIsMain() -> Bool { Thread.isMainThread }

}
