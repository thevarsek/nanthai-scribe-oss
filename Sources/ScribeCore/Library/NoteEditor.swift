import Foundation
import NaturalLanguage
import Observation

/// A rewrite owns a snapshot, not the live text. Typing during inference never gets overwritten.
@MainActor
@Observable
public final class NoteEditor {
    public var text: String {
        didSet {
            guard text != oldValue else { return }
            refineHighlight = nil
            targetHighlightRange = nil
            revision += 1
            if !opening {
                var note = currentNote?(original.id) ?? original
                note.save(text)
                autosave?(note)
            }
        }
    }
    public var selection: NSRange {
        didSet { if selection != oldValue { refineHighlight = nil } }
    }
    /// Presentation-only metadata; persisted notes contain a plain String.
    public private(set) var refineHighlight: RefineHighlight?
    public struct RefineHighlight: Equatable, Sendable {
        public let id = UUID()
        public let range: NSRange
    }
    public private(set) var busyRange: NSRange?
    public private(set) var targetHighlightRange: NSRange?
    public var showChanges = false {
        didSet { if showChanges { refineHighlight = nil } }
    }
    public var changes: [NoteDiff.Segment] { NoteDiff.segments(original: original.original ?? original.text, current: text) }
    public var failure: String?
    public private(set) var original: Note
    public private(set) var revision = 0
    @ObservationIgnored public weak var undoManager: UndoManager?
    @ObservationIgnored public var autosave: ((Note) -> Void)?
    @ObservationIgnored private var opening = false
    private let currentNote: ((UUID) -> Note?)?
    private var operationID: UUID?
    @ObservationIgnored private var rewriteTask: Task<String, Error>?
    public static let failureHint = "Couldn't refine. Try again."
    public var isRunning: Bool { operationID != nil }
    public var hasChanges: Bool { text != (original.original ?? original.text) }

    public init(note: Note, autosave: ((Note) -> Void)? = nil, currentNote: ((UUID) -> Note?)? = nil) {
        self.autosave = autosave
        self.currentNote = currentNote
        original = note
        text = note.text
        selection = NSRange(location: (note.text as NSString).length, length: 0)
    }

    public func open(_ note: Note) {
        cancel()
        showChanges = false
        undoManager?.removeAllActions()
        opening = true
        original = note
        text = note.text
        opening = false
        selection = NSRange(location: (text as NSString).length, length: 0)
        failure = nil
    }

    /// Restoring only an edited source avoids persisting an untouched take when retention is Off.
    @discardableResult
    public func saveAsCopy(now: Date = .now) -> Note {
        let copy = original.copy(text: text, now: now)
        if let current = currentNote?(original.id), current.text == text, text != original.text {
            var restored = original
            restored.save(restored.text, now: now)
            autosave?(restored)
        }
        autosave?(copy)
        open(copy)
        return copy
    }

    public func cancel() {
        refineHighlight = nil
        targetHighlightRange = nil
        operationID = nil
        busyRange = nil
        rewriteTask?.cancel()
        rewriteTask = nil
    }

    public func revert() { showChanges = false; replace(text: original.original ?? original.text, selection: NSRange(location: 0, length: 0), action: "Revert to original") }

    /// Programmatic edits share the native text view's undo manager, one snapshot per result.
    public func replace(text: String, selection: NSRange, action: String) {
        let previousText = self.text
        let previousSelection = self.selection
        undoManager?.beginUndoGrouping()
        undoManager?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                editor.replace(text: previousText, selection: previousSelection, action: action)
            }
        }
        undoManager?.setActionName(action)
        undoManager?.endUndoGrouping()
        self.text = text
        self.selection = selection
        failure = nil
    }

    public func insertDictation(_ text: String, at cursor: NSRange? = nil) {
        insert(text, at: cursor, action: "Dictation")
    }

    public func paste(_ text: String) {
        guard !text.isEmpty else { return }
        if self.text.isEmpty, original.text.isEmpty { original.origin = .pasted }
        insert(text, action: "Paste")
    }

    private func insert(_ text: String, at cursor: NSRange? = nil, action: String) {
        guard !text.isEmpty else { return }
        let target = validRange(cursor ?? selection) ?? NSRange(location: (self.text as NSString).length, length: 0)
        let result = (self.text as NSString).replacingCharacters(in: target, with: text)
        replace(text: result, selection: NSRange(location: target.location + (text as NSString).length, length: 0), action: action)
    }

    public func apply(_ preset: RewritePrompts.Preset, rewriter: any TextRewriter,
                      tone: RewriteTone = .natural, outputLanguage: String = "", languages: [String] = [],
                      dictionary: [DictionaryEntry] = [], timeout: Duration = .seconds(20)) async {
        guard !isRunning else { return }
        let selectedRange = validRange(selection).flatMap { $0.length > 0 ? $0 : nil }
        let range = selectedRange ?? NSRange(location: 0, length: (text as NSString).length)
        guard range.length > 0 else { return }
        let snapshot = text
        let storedVersion = currentNote?(original.id)
        let version = revision
        let id = UUID()
        operationID = id
        busyRange = range
        targetHighlightRange = selectedRange
        failure = nil
        let selected = (snapshot as NSString).substring(with: range)
        let target = Self.translationTarget(text: selected, outputLanguage: outputLanguage, languages: languages)
        let instruction = RewritePrompts.presetInstruction(preset, translateTo: target)
        let request = RewriteRequest(task: .edit(instruction: instruction, selection: selected), transcript: instruction,
            context: RewriteContext(draftBefore: String((snapshot as NSString).substring(to: range.location).suffix(600)),
                                    tone: tone, dictionaryTerms: DictionaryEntry.terms(in: dictionary)))
        do {
            if timeout <= .zero { throw RewriteError.timedOut }
            let work = Task {
                try await RewriteDeadline.run(timeout: timeout) {
                    guard await rewriter.isAvailable() else { throw RewriteError.unavailable("Refine is unavailable.") }
                    return try await rewriter.rewrite(request)
                }
            }
            rewriteTask = work
            let result = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: { work.cancel() }
            guard operationID == id else { return }
            guard revision == version, !Task.isCancelled else { throw CancellationError() }
            if let currentNote {
                guard let storedVersion, currentNote(original.id) == storedVersion else { throw CancellationError() }
            }
            let replaced = DictionaryReplacement.apply(to: result, dictionary: dictionary)
            guard !replaced.isEmpty else { throw RewriteError.rejected("Empty result") }
            let updated = (snapshot as NSString).replacingCharacters(in: range, with: replaced)
            let resultRange = NSRange(location: range.location, length: (replaced as NSString).length)
            let cursor = selectedRange == nil ? NSRange(location: NSMaxRange(resultRange), length: 0) : resultRange
            replace(text: updated, selection: cursor,
                    action: preset.rawValue.capitalized)
            refineHighlight = RefineHighlight(range: resultRange)
        } catch {
            if operationID == id { failure = Self.failureHint }
        }
        if operationID == id { operationID = nil; busyRange = nil; targetHighlightRange = nil; rewriteTask = nil }
    }

    public static func translationTarget(text: String, outputLanguage: String, languages: [String]) -> Locale {
        if !outputLanguage.isEmpty { return Locale(identifier: outputLanguage) }
        if NLLanguageRecognizer.dominantLanguage(for: text) == .english,
           let other = languages.first(where: { Locale(identifier: $0).language.languageCode?.identifier != "en" }) {
            return Locale(identifier: other)
        }
        return Locale(identifier: "en")
    }

    private func validRange(_ range: NSRange) -> NSRange? {
        guard range.location != NSNotFound, Range(range, in: text) != nil else { return nil }
        return range
    }
}
