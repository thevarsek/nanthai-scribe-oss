import Foundation

public extension Meeting {
    var canRetryTranscription: Bool { state != .recording && processingError != nil && !audio.isEmpty }

    /// Starting again preserves reviewed turns until a replacement transcript has succeeded.
    mutating func beginRetry() -> Bool {
        guard canRetryTranscription else { return false }
        state = .processing
        transcriptionRetryPending = true
        processingError = nil
        summaryError = nil
        return true
    }

    /// An edit is reusable only when its time interval still identifies exactly one turn.
    mutating func replaceTranscript(_ incoming: [MeetingTurn]) {
        guard !incoming.isEmpty else { return }
        transcriptionRetryPending = false
        let previous = turns
        turns = incoming.map { new in
            let matches = previous.filter { abs($0.start - new.start) <= 0.1 && abs($0.end - new.end) <= 0.1 }
            guard matches.count == 1, let edit = matches.first, edit.isEdited,
                  incoming.filter({ abs($0.start - edit.start) <= 0.1 && abs($0.end - edit.end) <= 0.1 }).count == 1 else { return new }
            var preserved = new
            preserved.id = edit.id; preserved.text = edit.text; preserved.isEdited = true
            return preserved
        }
        let previousSpeakers = speakers
        speakers = MeetingAlignment.speakers(for: turns).map { new in previousSpeakers.first { $0.id == new.id } ?? new }
        if previous != turns { summaryNeedsUpdate = true }
    }
}
