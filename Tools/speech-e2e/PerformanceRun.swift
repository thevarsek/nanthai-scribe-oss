import AVFoundation
import Darwin
import Foundation
@_spi(Performance) import ScribeCore
import Speech
import Synchronization

/// Replays a fixture through the shipping pipeline, with content-free timing and memory output.
/// Usage: speech-e2e clip.wav en_US,it_IT --performance --runs 3 [--realtime] [--inspect-seconds 20]
@MainActor enum PerformanceRun {
    static func run(clip: URL, locales: [Locale]) async throws {
        let arguments = CommandLine.arguments
        func integer(_ flag: String, default fallback: Int) -> Int {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return fallback }
            return Int(arguments[index + 1]) ?? fallback
        }
        let root = URL(filePath: "/tmp", directoryHint: .isDirectory).appending(path: "speech-performance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let samples = Mutex<[SpeechPerformanceSample]>([])
        let heartbeat = Mutex<[Double]>([])
        let monitor = Task.detached {
            while !Task.isCancelled {
                let scheduled = ContinuousClock.now.advanced(by: .milliseconds(16))
                do { try await Task.sleep(until: scheduled) } catch { break }
                await MainActor.run {
                    heartbeat.withLock { $0.append(milliseconds(scheduled.duration(to: .now))) }
                }
            }
        }
        defer { monitor.cancel() }
        print("performance pid=\(getpid()) languages=\(locales.count) realtime=\(arguments.contains("--realtime")) baselineRSSMiB=\(residentMiB())")
        fflush(nil)
        for run in 1...max(1, integer("--runs", default: 1)) {
            samples.withLock { $0.removeAll(keepingCapacity: true) }
            heartbeat.withLock { $0.removeAll(keepingCapacity: true) }
            weak var released: LiveTranscriber?
            let finishMs: Double
            var feedMs = 0.0
            var characters = 0
            var locale = "none"
            do {
                let transcriber = LiveTranscriber(recoveryRoot: root)
                released = transcriber
                transcriber.onPerformanceSample = { sample in samples.withLock { $0.append(sample) } }
                transcriber.onUpdate = { characters = $0.utf8.count }
                let (format, sink) = try await transcriber.start(locales: locales)
                let file = try AVAudioFile(forReading: clip)
                guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw ScribeError.noAudioFormat }
                let feeder = AudioFileFeeder(file)
                let start = ContinuousClock.now
                var frames: Int64 = 0
                while true {
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * 0.03))!
                    var error: NSError?
                    let status = converter.convert(to: buffer, error: &error) { requested, state in feeder.next(requested, state: state) }
                    if let error { throw error }
                    if let error = feeder.error { throw error }
                    if buffer.frameLength > 0 {
                        sink.yield(AnalyzerInput(buffer: buffer))
                        frames += Int64(buffer.frameLength)
                        if arguments.contains("--realtime") {
                            try await Task.sleep(until: start.advanced(by: .seconds(Double(frames) / format.sampleRate)))
                        }
                    }
                    if status == .endOfStream { break }
                    if status == .error { throw ScribeError.noAudioFormat }
                }
                feedMs = milliseconds(start.duration(to: .now))
                let endOfInput = ContinuousClock.now
                let result = await transcriber.finish()
                finishMs = milliseconds(endOfInput.duration(to: .now))
                characters = result.text.utf8.count
                locale = result.locale?.identifier ?? "none"
                if let index = arguments.firstIndex(of: "--reference-file"), index + 1 < arguments.count {
                    let reference = try String(contentsOfFile: arguments[index + 1], encoding: .utf8)
                    let score = WordErrorScore(reference: reference, actual: result.text)
                    print("run=\(run) referenceWords=\(score.words) wordErrors=\(score.errors) wer=\(score.rate)")
                }
                print("run=\(run) appleErrors=\(transcriber.appleErrors) batchErrors=\(transcriber.batchErrors)")
                await transcriber.cancel()
            }
            let measured = samples.withLock { $0 }
            for checkpoint in [30.0, 60, 120, 180] {
                for phase in ["apply", "publish"] {
                    let bucket = measured.filter { $0.phase == phase && $0.audioEnd > checkpoint - 15 && $0.audioEnd <= checkpoint }
                    print("run=\(run) audio=\(Int(checkpoint)) \(phase) \(summary(bucket.map(\.milliseconds))) mainSamples=\(bucket.filter(\.onMainThread).count)")
                }
            }
            for phase in Set(measured.map(\.phase)).subtracting(["apply"]).sorted() {
                print("run=\(run) \(phase) \(summary(measured.filter { $0.phase == phase }.map(\.milliseconds))) audioEnd=\(measured.first { $0.phase == phase }?.audioEnd ?? -1)")
            }
            print("run=\(run) feedMs=\(feedMs) finishMs=\(finishMs) finalBytes=\(characters) locale=\(locale) mainDelay \(summary(heartbeat.withLock { $0 })) released=\(released == nil) RSSMiB=\(residentMiB())")
            try await Task.sleep(for: .seconds(2))
            print("run=\(run) settledRSSMiB=\(residentMiB()) settledReleased=\(released == nil)")
            fflush(nil)
        }
        let inspection = integer("--inspect-seconds", default: 0)
        if inspection > 0 {
            print("inspect pid=\(getpid()) seconds=\(inspection)")
            fflush(nil)
            try await Task.sleep(for: .seconds(inspection))
        }
    }

    nonisolated static func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }

    nonisolated static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return "n=0" }
        return String(format: "n=%d p50=%.3f p95=%.3f max=%.3f", sorted.count, sorted[sorted.count / 2], sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], sorted.last!)
    }

    private static func residentMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }
}
