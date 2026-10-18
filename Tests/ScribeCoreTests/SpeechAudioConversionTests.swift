import AVFoundation
import XCTest
@testable import ScribeCore

final class SpeechAudioConversionTests: XCTestCase {
    func testVoiceProcessingKeepsMicrophoneChannelInsteadOfDownmixingExtraChannels() throws {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 7))
        let source = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                               interleaved: false, channelLayout: layout))
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                               channels: 1, interleaved: false))
        let converter = try XCTUnwrap(SpeechAudioConversion.converter(from: source, to: target, voiceProcessing: true))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 32))
        input.frameLength = 32
        for channel in 0..<7 {
            for frame in 0..<32 { input.floatChannelData![channel][frame] = channel == 0 ? 0.25 : -0.25 }
        }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 64))
        let feeder = ConversionTestFeeder(input)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in feeder.next(status) }
        XCTAssertNil(error)
        XCTAssertEqual(output.frameLength, 32)
        for frame in 0..<Int(output.frameLength) {
            XCTAssertEqual(output.floatChannelData![0][frame], 0.25, accuracy: 0.0001)
        }
    }
}

private final class ConversionTestFeeder: @unchecked Sendable {
    private var input: AVAudioPCMBuffer?
    init(_ input: AVAudioPCMBuffer) { self.input = input }
    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let input else { status.pointee = .noDataNow; return nil }
        self.input = nil
        status.pointee = .haveData
        return input
    }
}
