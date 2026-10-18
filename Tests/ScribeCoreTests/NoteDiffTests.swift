import Foundation
import Testing
@testable import ScribeCore

struct NoteDiffTests {
    @Test(arguments: [
        ("Ci vediamo domani alle dieci.", "Ci vediamo venerdì alle dieci."),
        ("Wir treffen uns morgen im Büro.", "Wir treffen uns heute im Büro."),
        ("明日は東京に行きます。", "明日は京都に行きます。"),
        ("你好世界，明天见。", "你好朋友，明天见。"),
        ("Hello  👋\nworld!", "Hello 👋\nteam!"), ("", "New"), ("Old", ""), ("Same", "Same")
    ]) func diffPreservesBothVersionsAndFindsChanges(pair: (String, String)) {
        let (original, current) = pair
        let segments = NoteDiff.segments(original: original, current: current)
        #expect(segments.filter { $0.kind == .unchanged || $0.kind == .removed }.map(\.text).joined() == original)
        #expect(segments.filter { $0.kind == .unchanged || $0.kind == .inserted }.map(\.text).joined() == current)
        #expect(segments.contains { $0.kind != .unchanged } == (original != current))
        if !original.isEmpty, !current.isEmpty, original != current {
            #expect(segments.contains { $0.kind == .unchanged })
        }
    }

    @Test func replacedWordsAreVisiblySeparated() {
        let segments = NoteDiff.segments(original: "bring the notes to me", current: "bring the agenda to me")
        let shown = segments.map(\.text).joined()
        #expect(shown.contains("notes agenda"))
        #expect(!NoteDiff.segments(original: "東京へ行く", current: "大阪へ行く").contains { $0.kind == .gap })
    }

    @Test func originalSurvivesEditingEncodingReopeningAndCopying() throws {
        var note = Note(text: "Original", origin: .typed)
        note.save("Edited")
        let reopened = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(reopened.original == "Original")
        #expect(reopened.isEdited)
        #expect(reopened.copy().original == "Edited")
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        legacy.removeValue(forKey: "original")
        let migrated = try JSONDecoder().decode(Note.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(migrated.original == "Edited")
    }
}
