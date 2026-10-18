import AVFoundation
import FluidAudio
import Foundation

public enum MeetingDiarizer {
    /// Never call FluidAudio's load(from:) or download(): both can access the network.
    public static func diarize(file: URL, modelDirectory: URL, offset: Double = 0) async throws -> [SpeakerInterval] {
        guard ModelStore.isInstalled(ModelCatalog.meetingDiarizer, at: modelDirectory) else {
            throw RewriteError.unavailable("Download Meeting speakers in Settings › Meetings to identify speakers.")
        }
        let work = Task.detached(priority: .utility) {
            let models = try DiarizerModels.load(
                localSegmentationModel: modelDirectory.appending(path: "pyannote_segmentation.mlmodelc"),
                localEmbeddingModel: modelDirectory.appending(path: "wespeaker_v2.mlmodelc"))
            let manager = DiarizerManager(config: .init(clusteringThreshold: 0.5))
            manager.initialize(models: models)
            defer { manager.cleanup() }
            let converter = AudioConverter()
            let samples = try converter.resampleAudioFile(file)
            try Task.checkCancellation()
            let result = try manager.performCompleteDiarization(samples, sampleRate: 16_000)
            try Task.checkCancellation()
            return result.segments.map {
                SpeakerInterval(speakerID: $0.speakerId, start: offset + Double($0.startTimeSeconds),
                                end: offset + Double($0.endTimeSeconds))
            }
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}
