import AVFoundation
import Foundation
import Testing
@testable import ScribeCore

@MainActor @Suite struct MeetingPlaybackTests {
    @Test func segmentOffsetsSeekAndSpeedShareOneClock() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR3-playback-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        do {
            let output = try AVAudioFile(forWriting: root.appending(path: "part.caf"), settings: format.settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)); buffer.frameLength = 16_000
            try output.write(from: buffer)
        }
        let meeting = Meeting(title: "Fixture", audio: [.init(stream: "system", file: "part.caf", offset: 2)])
        let player = MeetingPlayback(); player.load(meeting, folder: root)
        #expect(player.hasAudio)
        #expect(abs(player.duration - 3) < 0.01)
        player.seek(-4); #expect(player.position == 0)
        player.seek(100); #expect(player.position == player.duration)
        player.seek(.nan); #expect(player.position == 0)
        player.cycleSpeed(); #expect(player.speed == 1.5)
        player.cycleSpeed(); #expect(player.speed == 2)
        player.cycleSpeed(); #expect(player.speed == 1)
        player.preparePlayback = { throw CocoaError(.fileReadUnknown) }
        player.play()
        #expect(!player.isPlaying)
        #expect(player.error == "Couldn't play this recording.")
        var prepared = false
        player.preparePlayback = { prepared = true }
        player.play()
        #expect(prepared && player.error == nil)
        try await Task.sleep(for: .milliseconds(250))
        #expect(player.isPlaying && player.position > 0 && player.position < 1)
        player.pause()
        let paused = player.position
        try await Task.sleep(for: .milliseconds(150))
        #expect(player.position == paused)
        player.stop(); #expect(player.position == 0 && !player.isPlaying)
    }
    @Test func absentAudioHidesPlayerAndDoesNotStartAClock() {
        let player = MeetingPlayback()
        player.load(Meeting(title: "Transcript only"), folder: URL(filePath: "/nonexistent"))
        var prepared = false
        player.preparePlayback = { prepared = true }
        player.play()
        #expect(!prepared)
        #expect(!player.hasAudio && !player.isPlaying && player.duration == 0)
    }
}
