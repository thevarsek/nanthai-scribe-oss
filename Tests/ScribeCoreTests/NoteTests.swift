import Foundation
import Testing
@testable import ScribeCore

@Suite struct NoteTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func bothLegacyFormatsPreserveIdentityDatesAndPins() throws {
        for pinned in [false, true] {
            let id = UUID()
            var object: [String: Any] = ["id": id.uuidString, "date": now.timeIntervalSinceReferenceDate, "text": "Hallo 👋\nCiao"]
            if pinned { object["pinned"] = true }
            let notes = try JSONDecoder().decode([Note].self, from: JSONSerialization.data(withJSONObject: [object]))
            let note = try #require(notes.first)
            #expect(note.id == id)
            #expect(note.createdAt == now)
            #expect(note.modified == now)
            #expect(note.text == "Hallo 👋\nCiao")
            #expect(note.origin == .dictation)
            #expect(note.isRetained == pinned)
            #expect(try JSONDecoder().decode([Note].self, from: JSONEncoder().encode(notes)) == notes)
        }
    }

    @Test func retentionOnlyExpiresUntouchedDictations() {
        let ages: [TimeInterval] = [0, 86_400, 86_401, 30 * 86_400, 30 * 86_400 + 1]
        let untouched = ages.map { Note(date: now.addingTimeInterval(-$0), text: "Take") }
        var edited = untouched.last!
        edited.save("Edited", now: now)
        let kept = [edited, Note(createdAt: .distantPast, text: "Typed", origin: .typed),
                    Note(createdAt: .distantPast, text: "Pasted", origin: .pasted),
                    Note(date: .distantPast, text: "Pinned", pinned: true), untouched.last!.copy(now: .distantPast)]
        #expect(NoteRetention.off.prune(untouched + kept, now: now) == kept)
        #expect(NoteRetention.oneDay.prune(untouched + kept, now: now) == Array(untouched.prefix(2)) + kept)
        #expect(NoteRetention.thirtyDays.prune(untouched + kept, now: now) == Array(untouched.prefix(4)) + kept)
        #expect(NoteRetention.forever.prune(untouched + kept, now: now) == untouched + kept)
    }

    @Test func copyLinksSourceAndDoesNotChangeOriginal() {
        let original = Note(date: now, text: "Original")
        let copy = original.copy(text: "Updated", now: now.addingTimeInterval(10))
        #expect(copy.id != original.id)
        #expect(copy.sourceID == original.id)
        #expect(copy.modified == copy.createdAt)
        #expect(copy.isRetained)
        #expect(original.text == "Original")
    }

    @Test func pinsGroupOnceAndSurviveEveryRetentionPolicy() throws {
        let pinned = Note(date: now.addingTimeInterval(-100 * 86_400), text: "Pinned", pinned: true)
        let today = Note(date: now, text: "Today")
        let sections = NoteSection.sections([today, pinned], now: now)
        #expect(sections.map(\.title) == ["Pinned", "Today"])
        #expect(sections.flatMap(\.notes).count == 2)
        #expect(NoteSection.sections([today, pinned], search: "Pinned", now: now).map(\.title) == ["Pinned"])
        for retention in NoteRetention.allCases { #expect(retention.prune([pinned], now: now) == [pinned]) }
        #expect(try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(pinned)).pinned)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(today)) as? [String: Any])
        legacy.removeValue(forKey: "pinned")
        #expect(try !JSONDecoder().decode(Note.self, from: JSONSerialization.data(withJSONObject: legacy)).pinned)
    }

    @Test func sectionsSearchAllContentAndUseCalendarDays() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        let notes = [Note(date: today, text: "Today"), Note(date: today.addingTimeInterval(-1), text: "Yesterday\nFind me"),
                     Note(date: today.addingTimeInterval(-2 * 86_400), text: "Earlier")]
        #expect(NoteSection.sections(notes, now: now, calendar: calendar).map(\.title) == ["Today", "Yesterday", "Earlier"])
        #expect(NoteSection.sections(notes, search: "find me", now: now, calendar: calendar).flatMap(\.notes).map(\.id) == [notes[1].id])
    }
}

@MainActor
@Suite struct NoteEditorTests {
    @Test func refineHighlightIsTransientAndSavedTextIsPlain() async throws {
        var saved: Note?
        let editor = NoteEditor(note: Note(text: "Before hello after"), autosave: { saved = $0 })
        editor.selection = NSRange(location: 7, length: 5)
        await editor.apply(.shorter, rewriter: NoteFixtureRewriter(results: ["Hi"]))
        #expect(editor.refineHighlight?.range == NSRange(location: 7, length: 2))
        let data = try JSONEncoder().encode(#require(saved))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["text"] as? String == "Before Hi after")
        #expect(object["refineHighlight"] == nil)
        #expect(object["attributes"] == nil)
        editor.selection = NSRange(location: 0, length: 0)
        #expect(editor.refineHighlight == nil)
        await editor.apply(.shorter, rewriter: NoteFixtureRewriter(results: ["Again"]))
        #expect(editor.refineHighlight != nil)
        editor.text += "!"
        #expect(editor.refineHighlight == nil)
    }

    @Test func runningSelectionTargetBecomesTheResultHighlight() async {
        let editor = NoteEditor(note: Note(text: "Before hello after"))
        editor.selection = NSRange(location: 7, length: 5)
        let task = Task { await editor.apply(.shorter, rewriter: NoteFixtureRewriter(results: ["Hi"], delay: .milliseconds(60))) }
        for _ in 0..<100 where !editor.isRunning { await Task.yield() }
        #expect(editor.targetHighlightRange == NSRange(location: 7, length: 5))
        await task.value
        #expect(editor.targetHighlightRange == nil)
        #expect(editor.refineHighlight?.range == NSRange(location: 7, length: 2))
    }

    @Test func reopenedNoteCanRevertToItsPersistentOriginal() {
        var note = Note(text: "Creation text", origin: .typed)
        note.save("Saved edit")
        let editor = NoteEditor(note: note)
        #expect(editor.hasChanges)
        editor.showChanges = true
        editor.revert()
        #expect(editor.text == "Creation text")
        #expect(!editor.showChanges)
        #expect(!editor.hasChanges)
    }

    @Test func selectionChainsOnCurrentTextAndEachResultIsOneUndo() async throws {
        let editor = NoteEditor(note: Note(text: "Before hello 👋 after"))
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo
        editor.selection = NSRange(location: 7, length: 8)
        let model = NoteFixtureRewriter(results: ["Hi 👋", "Ciao 👋"])
        await editor.apply(.shorter, rewriter: model)
        #expect(editor.text == "Before Hi 👋 after")
        await editor.apply(.friendlier, rewriter: model)
        #expect(editor.text == "Before Ciao 👋 after")
        let requests = await model.requests
        #expect(requests[0].task == .edit(instruction: RewritePrompts.presetInstruction(.shorter), selection: "hello 👋"))
        #expect(requests[1].task == .edit(instruction: RewritePrompts.presetInstruction(.friendlier), selection: "Hi 👋"))
        undo.undo()
        #expect(editor.text == "Before Hi 👋 after")
        undo.undo()
        #expect(editor.text == "Before hello 👋 after")
        undo.redo()
        #expect(editor.text == "Before Hi 👋 after")
    }

    @Test func collapsedSelectionRewritesWholeTextWithToneAndDictionary() async throws {
        let editor = NoteEditor(note: Note(text: "Hello nant"))
        let model = NoteFixtureRewriter(results: ["Hi nant"])
        await editor.apply(.refine, rewriter: model, tone: .formal,
            dictionary: [DictionaryEntry(term: "NanthAi", variants: ["nant"])])
        #expect(editor.text == "Hi NanthAi")
        let request = try #require(await model.requests.first)
        #expect(request.task == .edit(instruction: RewritePrompts.presetInstruction(.refine), selection: "Hello nant"))
        #expect(request.context.tone == .formal)
        #expect(request.context.dictionaryTerms == ["NanthAi"])
    }

    @Test func failureUnavailableEmptyAndTimeoutLeaveTextAndSelectionUntouched() async {
        for mode in 0..<4 {
            let editor = NoteEditor(note: Note(text: "Keep this exactly."))
            editor.selection = NSRange(location: 5, length: 4)
            let model = NoteFixtureRewriter(results: [mode == 1 ? "" : "Changed"], available: mode != 0, fails: mode == 2)
            await editor.apply(.proofread, rewriter: model, timeout: mode == 3 ? .zero : .seconds(20))
            #expect(editor.text == "Keep this exactly.")
            #expect(editor.selection == NSRange(location: 5, length: 4))
            #expect(editor.failure == NoteEditor.failureHint)
            #expect(!editor.isRunning)
        }
    }

    @Test func typingDuringRewriteAndOpeningAnotherNoteNeverLoseEdits() async {
        let editor = NoteEditor(note: Note(text: "Original"))
        let model = NoteFixtureRewriter(results: ["Late"], delay: .milliseconds(50))
        let work = Task { await editor.apply(.clearer, rewriter: model) }
        while await model.requests.isEmpty { await Task.yield() }
        editor.text = "User typed"
        await work.value
        #expect(editor.text == "User typed")
        let second = Task { await editor.apply(.clearer, rewriter: model) }
        while await model.requests.count < 2 { await Task.yield() }
        editor.open(Note(text: "Another note"))
        await second.value
        #expect(editor.text == "Another note")
    }

    @Test func latePresetCannotOverwriteAnotherEditorsChangesOrResurrectADeletedNote() async {
        for deleted in [false, true] {
            let original = Note(text: "Original")
            var stored: Note? = original
            let editor = NoteEditor(note: original, autosave: { stored = $0 }, currentNote: { _ in stored })
            let model = NoteFixtureRewriter(results: ["Late result"], delay: .milliseconds(50))
            let work = Task { await editor.apply(.clearer, rewriter: model) }
            while await model.requests.isEmpty { await Task.yield() }
            if deleted { stored = nil }
            else { stored?.save("Newer edit") }
            await work.value
            #expect(editor.text == "Original")
            #expect(editor.failure == NoteEditor.failureHint)
            #expect(stored?.text == (deleted ? nil : "Newer edit"))
        }
    }

    @Test func presetCompletionAutosavesWithTheEditorOutOfView() async {
        let original = Note(text: "Original")
        var stored = original
        let editor = NoteEditor(note: original, autosave: { stored = $0 }, currentNote: { _ in stored })
        await editor.apply(.clearer, rewriter: NoteFixtureRewriter(results: ["Refined"]))
        #expect(stored.text == "Refined")
        #expect(stored.isKept)
    }

    @Test func saveAsCopyRestoresEditedSourceAndNeverSavesAnUntouchedSource() {
        for edited in [false, true] {
            let original = Note(text: "Original")
            var notes = [original.id: original]
            var writes: [UUID] = []
            let editor = NoteEditor(note: original, autosave: { notes[$0.id] = $0; writes.append($0.id) },
                                    currentNote: { notes[$0] })
            if edited { editor.text = "Changed" }
            writes = []
            let copy = editor.saveAsCopy()
            #expect(copy.id != original.id)
            #expect(copy.sourceID == original.id)
            #expect(copy.text == (edited ? "Changed" : "Original"))
            #expect(copy.isKept)
            #expect(editor.original.id == copy.id)
            #expect(notes[original.id]?.text == "Original")
            #expect(notes[original.id]?.isKept == edited)
            #expect(writes == (edited ? [original.id, copy.id] : [copy.id]))
        }
    }

    @Test func revertRestoresOpenedVersionAndIsUndoable() async {
        let editor = NoteEditor(note: Note(text: "Opened"))
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo
        await editor.apply(.refine, rewriter: NoteFixtureRewriter(results: ["Refined"]))
        editor.revert()
        #expect(editor.text == "Opened")
        undo.undo()
        #expect(editor.text == "Refined")
    }

    @Test func autosaveKeepsEachEditImmediatelyAndOpeningDoesNotCreateAnEdit() {
        var saved: [Note] = []
        let note = Note(text: "Original")
        let editor = NoteEditor(note: note, autosave: { saved.append($0) })
        editor.text = "Edited"
        #expect(saved.last?.text == "Edited")
        #expect(saved.last?.id == note.id)
        #expect(saved.last?.isKept == true)
        editor.revert()
        #expect(saved.last?.text == "Original")
        editor.open(Note(text: "Another"))
        #expect(saved.count == 2)
        editor.open(Note(text: "", origin: .typed))
        editor.paste("Pasted")
        #expect(saved.last?.origin == .pasted)
    }

    @Test func dictationInsertsAtUnicodeCursorAsOneUndoStep() {
        let editor = NoteEditor(note: Note(text: "👋 world"))
        editor.selection = NSRange(location: 3, length: 0)
        editor.insertDictation("beautiful ")
        #expect(editor.text == "👋 beautiful world")
    }
}

private actor NoteFixtureRewriter: TextRewriter {
    nonisolated let id = "fixture"
    var results: [String]
    let available: Bool
    let fails: Bool
    let delay: Duration
    var requests: [RewriteRequest] = []
    init(results: [String], available: Bool = true, fails: Bool = false, delay: Duration = .zero) {
        self.results = results; self.available = available; self.fails = fails; self.delay = delay
    }
    func isAvailable() async -> Bool { available }
    func rewrite(_ request: RewriteRequest) async throws -> String {
        requests.append(request)
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw RewriteError.rejected("Fixture") }
        return results.isEmpty ? "Late" : results.removeFirst()
    }
}
