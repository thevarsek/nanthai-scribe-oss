import Foundation
import ScribeCore
import Testing
@testable import ScribeMac

@MainActor struct M171PipelineTests {
    @Test func twoVoiceTTSThroughSharedPipelineAndSummary() async throws {
        guard MeetingFixtures.diarizerInstalled, await MeetingFixtures.installed("en_US") else {
            print("M17.1 E2E skipped: local diarization or speech assets unavailable.")
            return
        }
        let models = ModelStore()
        let appleAvailable = await AppleRewriter().isAvailable()
        guard appleAvailable || models.isInstalled(ModelCatalog.gemma) else {
            print("M17.1 E2E skipped: no local summary engine available.")
            return
        }
        let gemma = appleAvailable ? nil : GemmaRewriter(modelDirectory: models.directory(for: ModelCatalog.gemma))
        let folder = FileManager.default.temporaryDirectory.appending(path: "scribe-m171-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clips = [
            try MeetingFixtures.clip("Samantha", "The prototype is ready. Let's review accessibility before the launch on Friday. The budget stays the same for this quarter."),
            try MeetingFixtures.clip("Daniel", "I will arrange the review for Thursday and invite the support team to join us. I will send the release notes after the review."),
            try MeetingFixtures.clip("Samantha", "Thank you. Please include the mobile app in the accessibility review. We need the final schedule tomorrow morning."),
            try MeetingFixtures.clip("Daniel", "Agreed. I will send the updated schedule tomorrow morning and confirm the reviewers by lunchtime.")]
        defer { try? FileManager.default.removeItem(at: folder); clips.forEach { try? FileManager.default.removeItem(at: $0) } }
        let audio = folder.appending(path: "microphone-1.caf")
        let writer = try await MeetingFixtures.write(clips, to: audio)
        try writer.finish()
        let transcript = try await MeetingPipeline.transcribe([.init(stream: "you", file: audio.lastPathComponent, offset: 0)],
            folder: folder, languages: [Locale(identifier: "en_US")], parakeetDirectory: nil, diarizerDirectory: MeetingFixtures.diarizer, progress: { _, _ in })
        #expect(transcript.errors.isEmpty)
        var meeting = Meeting(title: "Synthetic planning meeting", speakers: MeetingAlignment.speakers(for: transcript.turns), turns: transcript.turns)
        #expect(meeting.speakers.count >= 2)
        meeting.summary = try await MeetingSummarizer(gemma: gemma).summarize(meeting)
        #expect(meeting.summary?.bullets.isEmpty == false)
        await gemma?.unload()
        print("M17.1 E2E: \(meeting.speakers.count) speakers, \(meeting.summary?.bullets.count ?? 0) summary bullets.")
    }
}
