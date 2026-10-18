import AVFoundation

/// Voice I/O exposes multichannel capture on some devices. Select the first microphone
/// channel explicitly so a surround layout cannot map mono speech to silence.
public enum SpeechAudioConversion {
    public static func converter(from source: AVAudioFormat, to target: AVAudioFormat,
                                 voiceProcessing: Bool) -> AVAudioConverter? {
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        if voiceProcessing, source.channelCount > 1, target.channelCount == 1 {
            converter.channelMap = [0]
        }
        return converter
    }
}
