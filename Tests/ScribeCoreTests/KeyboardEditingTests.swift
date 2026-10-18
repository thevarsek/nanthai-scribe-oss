import Foundation
import Testing
@testable import ScribeCore

@Suite struct KeyboardEditingTests {
    @Test func deleteWaitsThenAcceleratesFromCharactersToWords() {
        var repeatKey = DeleteRepeat()
        #expect(repeatKey.repeatIfDue(elapsed: 0.499) == nil)
        #expect(!repeatKey.hasRepeated)
        #expect(repeatKey.repeatIfDue(elapsed: 0.5) == .character)
        #expect(repeatKey.hasRepeated)
        #expect(repeatKey.repeatIfDue(elapsed: 0.59) == nil)
        #expect(repeatKey.repeatIfDue(elapsed: 0.6) == .character)
        #expect(repeatKey.repeatIfDue(elapsed: 1.9) == .character)
        #expect(repeatKey.repeatIfDue(elapsed: 2) == .word)
        #expect(repeatKey.repeatIfDue(elapsed: 2.24) == nil)
        #expect(repeatKey.repeatIfDue(elapsed: 2.25) == .word)
        #expect(DeleteRepeat().nextRepeat == 0.5)
    }

    @Test func wordsStopAtWhitespaceAndCountGraphemes() {
        #expect(DeleteRepeat.wordLength(before: "hello world") == 5)
        #expect(DeleteRepeat.wordLength(before: "hello world  ") == 7)
        #expect(DeleteRepeat.wordLength(before: "hello\n世界👨‍👩‍👧‍👦") == 3)
        #expect(DeleteRepeat.wordLength(before: "\t\n ") == 3)
        #expect(DeleteRepeat.wordLength(before: "") == 0)
        #expect(DeleteRepeat.wordLength(before: "こんにちは") == 5)
    }

    @Test func selectionMustStillMatchBeforeFirstInsertion() {
        let id = UUID()
        let rewrite = SelectionRewrite(original: "Ciao 👋\n世界", documentID: id)
        #expect(rewrite.canReplace(at: .init(documentID: id, before: "", after: "", selection: rewrite.original)))
        #expect(!rewrite.canReplace(at: .init(documentID: id, before: "", after: "", selection: "Ciao")))
        #expect(!rewrite.canReplace(at: .init(documentID: id, before: rewrite.original, after: "", selection: nil)))
        #expect(!rewrite.canReplace(at: .init(documentID: UUID(), before: "", after: "", selection: rewrite.original)))
    }

    @Test func presetsRetainOriginalAndUndoExpiresOrInvalidatesOnTyping() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let id = UUID()
        var rewrite = SelectionRewrite(original: "  Original 👋\n", documentID: id)
        let resultPosition = SelectionRewrite.Position(documentID: id, before: "Prefix. Rewritten.", after: " Tail", selection: nil)
        rewrite.didInsert("Rewritten.", at: resultPosition, now: now)
        #expect(rewrite.canReplace(at: resultPosition))
        #expect(rewrite.canUndo(at: resultPosition, now: now.addingTimeInterval(9.99)))
        #expect(!rewrite.canUndo(at: resultPosition, now: now.addingTimeInterval(10)))
        var typed = resultPosition
        typed.before! += "a"
        #expect(!rewrite.canReplace(at: typed))
        #expect(!rewrite.canUndo(at: typed, now: now))
        var moved = resultPosition
        moved.after = "Different tail"
        #expect(!rewrite.canReplace(at: moved))
        rewrite.didInsert("Shorter.", at: resultPosition, now: now.addingTimeInterval(2))
        #expect(rewrite.original == "  Original 👋\n")
        #expect(rewrite.result == "Shorter.")
        #expect(try JSONDecoder().decode(SelectionRewrite.self, from: JSONEncoder().encode(rewrite)) == rewrite)
    }
}
