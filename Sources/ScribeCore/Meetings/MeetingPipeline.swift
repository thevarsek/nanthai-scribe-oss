import Foundation

/// Shared Mac/iPhone processing. Each checkpoint can be persisted before later work is attempted.
public enum MeetingPipeline {
    public struct Transcript: Sendable {
        public var turns: [MeetingTurn]
        public var errors: [String]
    }
    /// Finds files created just before a crash, including AAC committed before its JSON snapshot.
    public static func recover(_ meeting: Meeting, folder: URL) -> Meeting {
        var result = meeting
        var segments = meeting.audio
        for index in segments.indices {
            let source = folder.appending(path: segments[index].file)
            let compressed = source.deletingPathExtension().appendingPathExtension("m4a")
            if !FileManager.default.fileExists(atPath: source.path), MeetingAudioFiles.hasAudio(compressed) {
                segments[index].file = compressed.lastPathComponent
            }
        }
        let names = Set(segments.map(\.file))
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var end = segments.map { $0.offset + (MeetingAudioFiles.duration(of: folder.appending(path: $0.file)) ?? 0) }.max() ?? 0
        for file in files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
            where file.lastPathComponent.hasPrefix("microphone-") && file.pathExtension == "caf" && !names.contains(file.lastPathComponent) && MeetingAudioFiles.hasAudio(file) {
            segments.append(.init(stream: MeetingAudioSegment.microphone, file: file.lastPathComponent, offset: end))
            end += MeetingAudioFiles.duration(of: file) ?? 0
        }
        result.audio = segments
        result.duration = max(result.duration, end)
        result.endedAt = result.endedAt ?? result.startedAt.addingTimeInterval(result.duration)
        if result.state == .recording { result.recovered = true }
        result.state = .processing
        return result
    }

    public static func transcribe(_ segments: [MeetingAudioSegment], folder: URL, languages: [Locale],
                                  parakeetDirectory: URL?, diarizerDirectory: URL, enabledLocales: [Locale]? = nil,
                                  progress: @Sendable (MeetingProgress.Step, MeetingProgress.Status) async -> Void,
                                  fraction: @escaping @Sendable (MeetingProgress.Step, Double) async -> Void = { _, _ in }) async throws -> Transcript {
        let segments = segments.filter { MeetingAudioFiles.hasAudio(folder.appending(path: $0.file)) }
        guard !segments.isEmpty else { throw RewriteError.unavailable("Recording was interrupted.") }
        let parakeet = parakeetDirectory.map { ParakeetTranscriber(modelDirectory: $0) }
        let urls = segments.map { folder.appending(path: $0.file) }
        let preferred = zip(segments, urls).filter { $0.0.stream == MeetingAudioSegment.microphone }.map(\.1)
            + zip(segments, urls).filter { $0.0.stream != MeetingAudioSegment.microphone }.map(\.1)
        let locale = await MeetingLanguage.detect(files: preferred, among: languages, parakeet: parakeet, enabledLocales: enabledLocales)
        try Task.checkCancellation()
        await progress(.transcribing, .active)
        var collected: [String: [MeetingTurn]] = [:]
        var errors: [String] = []
        // Bounded memory on the phone; a failed segment still preserves all other speech.
        for (index, pair) in Array(zip(segments, urls)).enumerated() {
            let (segment, url) = pair
            try Task.checkCancellation()
            do {
                collected[segment.stream, default: []] += try await MeetingTranscriber.transcribe(
                    file: url, locale: locale, speakerID: segment.stream == MeetingAudioSegment.microphone ? "you" : "unassigned",
                    offset: segment.offset, parakeet: parakeet, enabledLocales: enabledLocales) { completed in
                        await fraction(.transcribing, (Double(index) + completed) / Double(segments.count))
                    }
            } catch {
                try Task.checkCancellation()
                errors.append(error.localizedDescription)
            }
            await fraction(.transcribing, Double(index + 1) / Double(segments.count))
        }
        await progress(.transcribing, errors.isEmpty ? .done : .failed(errors.joined(separator: "\n")))
        if ModelStore.isInstalled(ModelCatalog.meetingDiarizer, at: diarizerDirectory) {
            await progress(.speakers, .active)
            do {
                for stream in [MeetingAudioSegment.microphone, MeetingAudioSegment.system] {
                    guard let turns = collected[stream], !turns.isEmpty else { continue }
                    let parts = segments.filter { $0.stream == stream }
                    var intervals: [SpeakerInterval] = []
                    for (index, segment) in parts.enumerated() {
                        let prefix = (stream == MeetingAudioSegment.microphone ? "room-" : "") + (parts.count > 1 ? "\(index + 1)-" : "")
                        intervals += try await MeetingDiarizer.diarize(file: folder.appending(path: segment.file), modelDirectory: diarizerDirectory, offset: segment.offset)
                            .map { .init(speakerID: prefix + $0.speakerID, start: $0.start, end: $0.end) }
                    }
                    if stream != MeetingAudioSegment.microphone || Set(intervals.map(\.speakerID)).count > 1 {
                        collected[stream] = MeetingAlignment.align(turns.map { var turn = $0; turn.speakerID = "unassigned"; return turn }, to: intervals)
                    }
                }
                await progress(.speakers, .done)
            } catch {
                try Task.checkCancellation()
                errors.append(error.localizedDescription)
                await progress(.speakers, .failed(error.localizedDescription))
            }
        }
        try Task.checkCancellation()
        return Transcript(turns: MeetingAlignment.merge((collected[MeetingAudioSegment.microphone] ?? []) + (collected[MeetingAudioSegment.system] ?? [])), errors: errors)
    }
}
