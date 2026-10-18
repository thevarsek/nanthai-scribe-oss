import Foundation

/// A speech model that transcribes a whole utterance at once (no live text), used for
/// languages Apple's streaming recognizer doesn't cover. Implementation: Parakeet v3 via
/// FluidAudio, an optional download.
///
/// It joins `LiveTranscriber`'s candidates at `finish()`: its transcript competes with the
/// Apple lanes through `LanguagePicker`, labelled with the language its text is written in.
public protocol BatchTranscriber: Sendable {
    var id: String { get }
    /// All languages the engine can recognize, including overlap with Apple.
    var languages: [Locale] { get }
    var sampleRate: Double { get }
    func isAvailable() async -> Bool
    /// - Parameter samples: mono Float32 PCM at `sampleRate`.
    func transcribe(samples: [Float], sampleRate: Double) async throws -> BatchTranscript
}

public struct BatchTranscript: Sendable, Equatable {
    public var text: String
    /// Mean token confidence 0…1 when the engine reports it.
    public var confidence: Double?

    public init(text: String, confidence: Double? = nil) {
        self.text = text
        self.confidence = confidence
    }
}

public extension BatchTranscriber {
    var sampleRate: Double { 16_000 }
}

/// A timed word from a batch engine, in seconds from the start of its audio.
public struct MeetingWord: Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}
