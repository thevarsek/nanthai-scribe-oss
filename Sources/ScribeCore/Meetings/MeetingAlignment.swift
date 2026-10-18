import Foundation

public struct SpeakerInterval: Sendable, Equatable {
    public var speakerID: String
    public var start: Double
    public var end: Double
    public init(speakerID: String, start: Double, end: Double) {
        self.speakerID = speakerID; self.start = start; self.end = end
    }
}

public enum MeetingAlignment {
    /// Word-sized speech results are assigned by total overlap; ties favour first appearance.
    /// Uncovered words stay explicitly unassigned rather than inventing a speaker identity.
    public static func align(_ segments: [MeetingTurn], to intervals: [SpeakerInterval]) -> [MeetingTurn] {
        let ordered = intervals.sorted { $0.start < $1.start }
        let ids = ordered.reduce(into: [String]()) { if !$0.contains($1.speakerID) { $0.append($1.speakerID) } }
        return segments.map { segment in
            guard segment.speakerID != "you" else { return segment }
            var result = segment
            var bestOverlap = 0.0
            result.speakerID = "unassigned"
            for id in ids {
                let overlap = ordered.filter { $0.speakerID == id }.reduce(0.0) {
                    $0 + max(0, min(segment.end, $1.end) - max(segment.start, $1.start))
                }
                if overlap > bestOverlap { bestOverlap = overlap; result.speakerID = id }
            }
            return result
        }
    }

    public static func merge(_ turns: [MeetingTurn], maximumGap: Double = 1.5) -> [MeetingTurn] {
        let sorted = turns.enumerated().sorted {
            $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start
        }.map(\.element)
        var result: [MeetingTurn] = []
        for turn in sorted where !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let last = result.last, last.speakerID == turn.speakerID,
               turn.start - last.end <= maximumGap {
                let index = result.count - 1
                let separator = turn.text.first?.isWhitespace == true || last.text.last?.isWhitespace == true ? "" : " "
                result[index].text += separator + turn.text
                result[index].end = max(last.end, turn.end)
            } else { result.append(turn) }
        }
        return result
    }

    public static func speakers(for turns: [MeetingTurn]) -> [MeetingSpeaker] {
        var result: [MeetingSpeaker] = []
        var number = 0
        for turn in turns where !result.contains(where: { $0.id == turn.speakerID }) {
            let name: String
            if turn.speakerID == "you" { name = "You" }
            else if turn.speakerID == "unassigned" { name = "Speaker" }
            else { number += 1; name = "Speaker \(number)" }
            result.append(.init(id: turn.speakerID, name: name))
        }
        return result
    }
}
