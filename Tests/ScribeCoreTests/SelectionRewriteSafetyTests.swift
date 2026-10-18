import Foundation
import Testing
@testable import ScribeCore

@MainActor
@Suite struct SelectionRewriteSafetyTests {
    let now = Date(timeIntervalSince1970: 10_000)

    @Test func committingOurMarkedRangePreservesOwnershipAndUndoDeadline() {
        let document = UUID()
        let selected = SelectionRewrite.Position(documentID: document, before: "Prefix ", after: " Tail", selection: "Replacement")
        var state = SelectionRewrite(original: "Original", at: selected)
        state.didInsert("Replacement", at: selected, now: now)
        let deadline = state.undoUntil
        let committed = SelectionRewrite.Position(documentID: document, before: "Prefix Replacement", after: " Tail", selection: nil)
        state.didCommitMarkedResult(at: committed)
        #expect(state.undoUntil == deadline)
        #expect(state.original == "Original")
        #expect(state.refusal(at: committed, unchangedInsertion: true) == nil)
        #expect(state.canUndo(at: committed, now: now.addingTimeInterval(9)))
        #expect(!state.canUndo(at: committed, now: now.addingTimeInterval(10)))
        state.didCommitMarkedResult(at: .init(documentID: UUID(), before: nil, after: nil, selection: nil))
        #expect(state.position == committed)
    }

    @Test func rapidTapsStartOnlyOneRequestAndLateResultsCannotApplyTwice() {
        let proxy = SelectionProxy(selection: "Original")
        var state = SelectionRewrite(original: proxy.selection!, at: proxy.rewritePosition)
        let id = UUID()
        #expect(state.begin(id: id, preset: "refine", path: "in-keyboard", now: now) == true)
        for _ in 0..<20 { #expect(state.begin(id: UUID(), preset: "shorter", path: "in-keyboard", now: now) == false) }
        #expect(state.apply("Result", id: id, to: proxy, now: now) == .replaced(6))
        let document = proxy.text
        #expect(state.apply("Late", id: id, to: proxy, now: now) == .refused(.requestChanged))
        #expect(proxy.text == document)
        #expect(proxy.replacements == 1)
        #expect(proxy.deletedCharacters == 0)
    }

    @Test func presetUndoPresetAlwaysRetainsExactOriginal() {
        let original = "  Original 👋 e\u{301}\r\nNext line.\n"
        let proxy = SelectionProxy(selection: original)
        var state = SelectionRewrite(original: original, at: proxy.rewritePosition)
        for preset in ["refine", "shorter"] {
            let id = UUID()
            #expect(state.original == original)
            #expect(state.begin(id: id, preset: preset, path: "in-keyboard", now: now) == true)
            #expect(state.apply("Result: " + preset, id: id, to: proxy, now: now) == .replaced(8 + preset.count))
        }
        #expect(state.undo(in: proxy, now: now) == .replaced(original.count))
        #expect(proxy.text == "Prefix " + original + " Tail")
        #expect(state.original == original)
        let id = UUID()
        #expect(state.begin(id: id, preset: "professional", path: "in-keyboard", now: now) == true)
        #expect(state.apply("Third result", id: id, to: proxy, now: now) == .replaced(12))
        #expect(proxy.text == "Prefix Third result Tail")
    }

    @Test func changedSelectionDuringGenerationDoesNotModifyAnything() {
        let proxy = SelectionProxy(selection: "Original")
        var state = SelectionRewrite(original: "Original", at: proxy.rewritePosition)
        let id = UUID()
        state.begin(id: id, preset: "refine", path: "in-keyboard", now: now)
        proxy.selection = "Different"
        let before = proxy.text
        #expect(state.apply("Result", id: id, to: proxy, now: now) == .refused(.selectionChanged))
        #expect(proxy.text == before)
        #expect(proxy.replacements == 0)
        #expect(proxy.deletedCharacters == 0)
    }

    @Test func fiveChainedPresetsReplaceOnlyLatestResultThenUndoRestoresOriginal() {
        let original = "  Original with 👋🏽, e\u{301}, and two lines.\r\nKeep this exact.\n"
        let proxy = SelectionProxy(selection: original)
        var state = SelectionRewrite(original: original, at: proxy.rewritePosition)
        let chain = [
            ("refine", "A refined version of the original."),
            ("shorter", "Short."),
            ("friendlier", "Hello 👋🏽! Here is a much longer, friendlier version of the original text."),
            ("bullets", "- First point 👨‍👩‍👧‍👦\n- Second point with e\u{301}\r\n- Third point"),
            ("professional", "Please review the original text. Thank you.")
        ]
        for (index, item) in chain.enumerated() {
            let started = now.addingTimeInterval(Double(index * 12))
            let id = UUID()
            #expect(state.original == original)
            #expect(state.begin(id: id, preset: item.0, path: "in-keyboard", now: started) == true)
            #expect(state.begin(id: UUID(), preset: "shorter", path: "in-keyboard", now: started) == false)
            #expect(state.flight?.id == id)
            #expect(state.apply(item.1, id: id, to: proxy, now: started.addingTimeInterval(1)) == .replaced(item.1.count))
            #expect(proxy.text == "Prefix " + item.1 + " Tail")
            #expect(state.original == original)
            #expect(state.canUndo(at: proxy.rewritePosition, now: started.addingTimeInterval(10.99)))
            #expect(!state.canUndo(at: proxy.rewritePosition, now: started.addingTimeInterval(11)))
            #expect(state.flight == nil)
        }
        let latest = now.addingTimeInterval(49)
        #expect(state.undo(in: proxy, now: latest.addingTimeInterval(9.99)) == .replaced(original.count))
        #expect(proxy.text == "Prefix " + original + " Tail")
        #expect(Array(proxy.text.utf8) == Array(("Prefix " + original + " Tail").utf8))
        #expect(proxy.replacements == 6)
        #expect(proxy.deletedCharacters == chain.reduce(0) { $0 + $1.1.count })
    }

    @Test func collapsedResultRequiresWholeResultContextDocumentAndNoUserEdit() {
        for reason in [SelectionRewrite.Refusal.contextChanged, .truncatedContext, .documentChanged, .interveningChange] {
            let proxy = SelectionProxy(selection: "Original")
            var state = insertedState(proxy: proxy, result: "A long result")
            switch reason {
            case .contextChanged: proxy.after = "Changed cursor position"
            case .truncatedContext: proxy.reportedBefore = "result"
            case .documentChanged: proxy.documentID = UUID()
            case .interveningChange: proxy.unchangedInsertion = false
            default: break
            }
            let before = proxy.text
            let deletions = proxy.deletedCharacters
            let id = UUID()
            state.begin(id: id, preset: "shorter", path: "in-keyboard", now: now)
            #expect(state.apply("New", id: id, to: proxy, now: now) == .refused(reason))
            #expect(proxy.text == before)
            #expect(proxy.deletedCharacters == deletions)
            #expect(state.undo(in: proxy, now: now) == .refused(reason))
            #expect(proxy.text == before)
        }
    }

    @Test func identicalResultAtAnotherContextIsRefused() {
        let proxy = SelectionProxy(selection: "Original")
        var state = insertedState(proxy: proxy, result: "Result")
        proxy.before = "Other prefix Result"
        let id = UUID()
        state.begin(id: id, preset: "shorter", path: "in-keyboard", now: now)
        #expect(state.apply("New", id: id, to: proxy, now: now) == .refused(.contextChanged))
        #expect(proxy.deletedCharacters == 0)
    }

    @Test func deletionCountsGraphemesIncludingZWJAccentsAndCRLF() {
        let result = "👋🏽👨‍👩‍👧‍👦é e\u{301}\r\n🇮🇹"
        #expect(result.count == 7)
        let proxy = SelectionProxy(selection: "Original")
        var state = insertedState(proxy: proxy, result: result)
        #expect(state.undo(in: proxy, now: now) == .replaced(8))
        #expect(proxy.deletedCharacters == result.count)
        #expect(proxy.text == "Prefix Original Tail")
    }

    @Test func failureAndTimeoutPreserveSelectionAndOriginal() {
        let proxy = SelectionProxy(selection: "Original")
        var state = SelectionRewrite(original: "Original", at: proxy.rewritePosition)
        let before = proxy.text
        let id = UUID()
        state.begin(id: id, preset: "refine", path: "in-keyboard", now: now)
        #expect(state.fail(id: id) == true)
        #expect(proxy.text == before)
        #expect(state.original == "Original")
        state.begin(id: id, preset: "refine", path: "in-keyboard", now: now)
        #expect(state.apply("Result", id: id, to: proxy, now: now.addingTimeInterval(20)) == .refused(.timeout))
        #expect(proxy.text == before)
        #expect(proxy.deletedCharacters == 0)
        #expect(proxy.replacements == 0)
    }

    @Test func deletionCannotCrossAGraphemeBoundaryIntoSurroundingText() {
        let proxy = SelectionProxy(selection: "Original")
        var state = insertedState(proxy: proxy, result: "Result\r")
        proxy.after = "\nTail"
        let before = proxy.text
        #expect(state.undo(in: proxy, now: now) == .refused(.graphemeBoundary))
        #expect(proxy.text == before)
        #expect(proxy.deletedCharacters == 0)
    }

    @Test func availableAfterContextPrefixMatchesWithoutAssumingAFullDocument() {
        let proxy = SelectionProxy(selection: "Original")
        var state = insertedState(proxy: proxy, result: "Result")
        proxy.after = " Ta"
        #expect(state.undo(in: proxy, now: now) == .replaced(8))
        #expect(proxy.text == "Prefix Original Ta")
    }

    @Test func recreationPreservesOriginalAndRefusesInterruptedOrDifferentDocument() throws {
        let proxy = SelectionProxy(selection: "Original")
        var state = SelectionRewrite(original: "Original", at: proxy.rewritePosition)
        let id = UUID()
        state.begin(id: id, preset: "refine", path: "in-keyboard", now: now)
        var restored = try JSONDecoder().decode(SelectionRewrite.self, from: JSONEncoder().encode(state))
        restored.fail(id: id)
        #expect(restored.original == "Original")
        #expect(restored.apply("Late", id: id, to: proxy, now: now) == .refused(.requestChanged))
        restored.begin(id: id, preset: "refine", path: "app", now: now)
        restored = try JSONDecoder().decode(SelectionRewrite.self, from: JSONEncoder().encode(restored))
        proxy.documentID = UUID()
        #expect(restored.apply("Late", id: id, to: proxy, now: now) == .refused(.documentChanged))
        #expect(proxy.text == "Prefix Original Tail")
        #expect(proxy.deletedCharacters == 0)
    }

    @Test func recreatedControllerCannotVerifyCollapsedEditHistory() throws {
        let proxy = SelectionProxy(selection: "Original")
        let state = insertedState(proxy: proxy, result: "Result")
        var restored = try JSONDecoder().decode(SelectionRewrite.self, from: JSONEncoder().encode(state))
        proxy.unchangedInsertion = false
        #expect(restored.undo(in: proxy, now: now) == .refused(.interveningChange))
        #expect(proxy.deletedCharacters == 0)
    }

    @Test func fiveThousandCharacterSelectionIsNotTruncated() {
        let original = String(repeating: "x", count: 5_000)
        let proxy = SelectionProxy(selection: original)
        var state = SelectionRewrite(original: original, at: proxy.rewritePosition)
        let id = UUID()
        state.begin(id: id, preset: "proofread", path: "in-keyboard", now: now)
        #expect(state.original.count == 5_000)
        #expect(state.apply(original + ".", id: id, to: proxy, now: now) == .replaced(5_001))
        #expect(state.undo(in: proxy, now: now) == .replaced(5_000))
        #expect(proxy.text == "Prefix " + original + " Tail")
    }

    @Test func disconnectedAndLegacyTargetsAreNotAccepted() {
        let proxy = SelectionProxy(selection: "Original")
        var state = SelectionRewrite(original: "Original", documentID: proxy.documentID)
        let id = UUID()
        state.begin(id: id, preset: "refine", path: "app", now: now)
        #expect(state.apply("Result", id: id, to: proxy, now: now) == .refused(.unverifiedTarget))
        proxy.documentID = SelectionRewrite.noDocument
        #expect(state.refusal(at: proxy.rewritePosition) == .disconnected)
        #expect(proxy.replacements == 0)
    }

    private func insertedState(proxy: SelectionProxy, result: String) -> SelectionRewrite {
        var state = SelectionRewrite(original: proxy.selection!, at: proxy.rewritePosition)
        let id = UUID()
        state.begin(id: id, preset: "refine", path: "in-keyboard", now: now)
        #expect(state.apply(result, id: id, to: proxy, now: now) == .replaced(result.count))
        return state
    }
}

@MainActor
private final class SelectionProxy: SelectionRewriteDocument {
    var documentID = UUID()
    var before = "Prefix "
    var after = " Tail"
    var selection: String?
    var reportedBefore: String?
    var unchangedInsertion = false
    var deletedCharacters = 0
    var replacements = 0
    var text: String { before + (selection ?? "") + after }
    var rewritePosition: SelectionRewrite.Position {
        .init(documentID: documentID, before: reportedBefore ?? before, after: after, selection: selection)
    }
    init(selection: String) { self.selection = selection }
    func replaceVerifiedText(_ text: String, deletingCharacters count: Int) {
        for _ in 0..<count { before.removeLast(); deletedCharacters += 1 }
        selection = nil
        before += text
        replacements += 1
        unchangedInsertion = true
    }
}
