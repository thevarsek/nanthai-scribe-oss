import AVFoundation
import Foundation
import Speech
import Synchronization
import Testing
@_spi(Performance) @testable import ScribeCore

/// Opt-in comparison of short-lived span analyzers against keeping the same backing
/// language model prepared. The latter costs an idle analyzer for the entire dictation.
@Suite(.serialized) struct SpeechSpanSetupTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIBE_SPAN_CLIP"] != nil))
    func compareFreshAndPrewarmedSpanSetup() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["SCRIBE_SPAN_CLIP"])
        let url = URL(filePath: path)
        let locale = Locale(identifier: "it_IT")
        for prewarmed in [false, true] {
            let samples = Mutex<[SpeechPerformanceSample]>([])
            let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                           attributeOptions: [.audioTimeRange, .transcriptionConfidence])
            let keeper = prewarmed ? SpeechAnalyzer(modules: [module]) : nil
            let prepare = ContinuousClock.now
            try await keeper?.prepareToAnalyze(in: nil)
            print("spanSetupComparison prewarmed=\(prewarmed) prepareMs=\(ms(prepare.duration(to: .now)))")
            do {
                var totals: [Double] = []
                for _ in 0..<5 {
                    let start = ContinuousClock.now
                    let result = try await SpeechFileTranscriber.transcribe(file: url, locale: locale, contextualStrings: [],
                        measure: { sample in samples.withLock { $0.append(sample) } })
                    totals.append(ms(start.duration(to: .now)))
                    #expect(!result.candidate.text.isEmpty)
                }
                let setup = samples.withLock { $0.map(\.milliseconds) }
                print("spanSetupComparison prewarmed=\(prewarmed) setupMs=\(setup) totalMs=\(totals)")
            } catch {
                await keeper?.cancelAndFinishNow()
                throw error
            }
            await keeper?.cancelAndFinishNow()
        }
    }

    private func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
