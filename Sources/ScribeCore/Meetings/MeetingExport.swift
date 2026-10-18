import Foundation

public enum MeetingExport {
    public static func transcript(_ meeting: Meeting) -> String {
        meeting.turns.map { "[\(MeetingTime.stamp($0.start))] \(meeting.speakerName($0.speakerID)): \($0.text)" }.joined(separator: "\n\n")
    }
    public static func summary(_ meeting: Meeting) -> String {
        guard let summary = meeting.summary else { return "" }
        return (summary.bullets.map { "• " + $0 } + summary.actions.map {
            "[\($0.done ? "x" : " ")] " + ($0.owner.map { $0 + ": " } ?? "") + $0.text
        }).joined(separator: "\n")
    }
    public static func plainText(_ meeting: Meeting) -> String {
        var lines = [meeting.title, meeting.startedAt.formatted() + " · " + MeetingTime.stamp(meeting.duration)]
        if let summary = meeting.summary {
            lines += ["", "Summary"] + summary.bullets.map { "• " + $0 } + ["", "Action items"]
            lines += summary.actions.map { "[\($0.done ? "x" : " ")] " + ($0.owner.map { $0 + ": " } ?? "") + $0.text }
        }
        if !meeting.notes.isEmpty { lines += ["", "Notes", meeting.notes] }
        return (lines + ["", "Transcript", transcript(meeting)]).joined(separator: "\n")
    }
    public static func markdown(_ meeting: Meeting) -> String {
        func escape(_ value: String) -> String {
            value.reduce(into: "") { out, character in
                if "\\`*_{}[]<>#|".contains(character) { out += "\\" }
                out.append(character)
            }
        }
        var lines = ["# " + escape(meeting.title), "", meeting.startedAt.formatted() + " · " + MeetingTime.stamp(meeting.duration)]
        if let summary = meeting.summary {
            lines += ["", "## Summary", ""] + summary.bullets.map { "- " + escape($0) } + ["", "## Action items", ""]
            lines += summary.actions.map { "- [\($0.done ? "x" : " ")] " + escape(($0.owner.map { $0 + ": " } ?? "") + $0.text) }
        }
        if !meeting.notes.isEmpty { lines += ["", "## Notes", "", escape(meeting.notes)] }
        lines += ["", "## Transcript", ""]
        lines += meeting.turns.map { "**\(escape(meeting.speakerName($0.speakerID)))** · \(MeetingTime.stamp($0.start))\n\n\(escape($0.text))\n" }
        return lines.joined(separator: "\n")
    }
}
