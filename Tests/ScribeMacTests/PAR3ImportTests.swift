import Foundation
import ScribeCore
import Testing
@testable import ScribeMac

@MainActor struct PAR3ImportTests {
    @Test func importedTTSUsesMeetingPipelineWithoutChangingOriginal() async throws {
        guard await MeetingFixtures.installed("en_US") else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR3-import-\(UUID())")
        let clip = try MeetingFixtures.clip("Samantha", "The launch is on Friday. I will send the schedule tomorrow morning.")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: clip) }
        let original = try Data(contentsOf: clip)
        let store = MeetingStore(root: root)
        let meeting = try await RecordingImport(url: clip).copy(from: clip, into: store, languages: ["en_US"], keepAudio: true)
        let result = try await MeetingPipeline.transcribe(meeting.audio, folder: store.directory(meeting.id),
            languages: [Locale(identifier: "en_US")], parakeetDirectory: nil,
            diarizerDirectory: root.appending(path: "NoSpeakerModel"), progress: { _, _ in })
        #expect(result.errors.isEmpty)
        #expect(!result.turns.isEmpty)
        #expect(result.turns.map(\.text).joined(separator: " ").lowercased().contains("friday"))
        #expect(try Data(contentsOf: clip) == original)
    }
}
