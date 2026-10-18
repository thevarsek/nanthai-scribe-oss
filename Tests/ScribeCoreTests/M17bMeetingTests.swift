import Foundation
import Testing
@testable import ScribeCore

struct M17bMeetingTests {
    @Test func legacyMeetingsDecodeWithoutNewFields() throws {
        let meeting = Meeting(title: "Legacy", turns: [.init(speakerID: "you", start: 1, end: 2, text: "Hello")])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(meeting)) as? [String: Any])
        json.removeValue(forKey: "notes"); json.removeValue(forKey: "recovered")
        var turns = try #require(json["turns"] as? [[String: Any]])
        turns[0].removeValue(forKey: "isEdited"); json["turns"] = turns
        let decoded = try JSONDecoder().decode(Meeting.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.notes.isEmpty && !decoded.recovered && !decoded.turns[0].isEdited)
    }

    @Test func editedTurnsAndNotesRoundTripInEveryScript() throws {
        var meeting = Meeting(title: "Planning", turns: [.init(speakerID: "you", start: 1, end: 2, text: "Original")])
        let original = meeting.turns[0]
        meeting.editTurn(original.id, text: original.text)
        #expect(!meeting.turns[0].isEdited)
        let corrected = "日本語 العربية हिन्दी italiano 👩🏽‍💻"
        meeting.editTurn(original.id, text: corrected)
        meeting.notes = "Next: [review] *draft*\n" + corrected
        meeting.recovered = true
        let decoded = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(meeting))
        #expect(decoded == meeting)
        #expect(decoded.turns[0].isEdited)
        #expect(decoded.turns[0].id == original.id && decoded.turns[0].start == original.start && decoded.turns[0].end == original.end)
        #expect(MeetingExport.transcript(decoded).contains(corrected))
        #expect(!MeetingExport.transcript(decoded).contains("Next:"))
        #expect(MeetingExport.plainText(decoded).contains("Notes\nNext: [review] *draft*"))
        #expect(MeetingExport.markdown(decoded).contains("## Notes\n\nNext: \\[review\\] \\*draft\\*"))
    }

    @Test func summaryCopyIncludesOnlySummaryAndActions() {
        let meeting = Meeting(title: "Title", turns: [.init(speakerID: "you", start: 0, end: 1, text: "Transcript")],
            summary: .init(bullets: ["Decision"], actions: [.init(text: "Send update", owner: "Jo", done: true)]), notes: "Private notes")
        #expect(MeetingExport.summary(meeting) == "• Decision\n[x] Jo: Send update")
        #expect(MeetingExport.summary(Meeting(title: "Empty")).isEmpty)
    }
}
