import AVFoundation
import Foundation
import ScribeCore
import XCTest

final class MeetingCapturePolicyTests: XCTestCase {
    func testPausedClockAndInterruptionExcludePausedTime() {
        let date = Date.now
        var clock = MeetingCaptureClock()
        clock.start(at: date); clock.pause(at: date.addingTimeInterval(10))
        XCTAssertEqual(clock.elapsed(at: date.addingTimeInterval(100)), 10)
        clock.resume(at: date.addingTimeInterval(100))
        clock.interruptionBegan(at: date.addingTimeInterval(110))
        XCTAssertTrue(clock.interruptionEnded(shouldResume: true, at: date.addingTimeInterval(200)))
        clock.stop(at: date.addingTimeInterval(210))
        XCTAssertEqual(clock.elapsed(at: date.addingTimeInterval(500)), 30)
        XCTAssertEqual(clock.state, .stopped)
    }
    func testResourceBoundaries() {
        XCTAssertFalse(MeetingCapturePolicy.canStart(freeBytes: 999_999_999))
        XCTAssertTrue(MeetingCapturePolicy.canStart(freeBytes: 1_000_000_000))
        XCTAssertFalse(MeetingCapturePolicy.shouldStop(elapsed: 14_399, battery: -1, freeBytes: 1_000_000_000))
        XCTAssertTrue(MeetingCapturePolicy.shouldStop(elapsed: 14_400, battery: 1, freeBytes: 1_000_000_000))
        XCTAssertTrue(MeetingCapturePolicy.shouldStop(elapsed: 1, battery: 0.05, freeBytes: 1_000_000_000))
    }
    func testRecoveryFindsUncommittedAudioAndCompressedCheckpoint() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        for index in 0..<1600 { buffer.floatChannelData?[0][index] = 0.01 }
        for name in ["microphone-1.caf", "microphone-2.caf"] {
            let file = try AVAudioFile(forWriting: folder.appending(path: name), settings: format.settings)
            try file.write(from: buffer)
        }
        let recording = Meeting(title: "Recovered", state: .recording, audio: [.init(stream: "you", file: "microphone-1.caf", offset: 0)])
        let recovered = MeetingPipeline.recover(recording, folder: folder)
        XCTAssertEqual(recovered.audio.count, 2)
        XCTAssertTrue(recovered.recovered)
        XCTAssertEqual(recovered.duration, 0.2, accuracy: 0.001)
        try MeetingAudioFiles.compress(folder.appending(path: "microphone-1.caf"), to: folder.appending(path: "microphone-1.m4a"))
        XCTAssertEqual(MeetingPipeline.recover(recovered, folder: folder).audio.first?.file, "microphone-1.m4a")
    }
}
