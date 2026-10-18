import AppKit
import ScribeCore
import ScribeUI
import SwiftUI

/// The native editor owns typing undo; preset snapshots use the same undo manager.
struct MacNoteTextEditor: NSViewRepresentable {
    let editor: NoteEditor

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = RefineTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.allowsUndo = true
        view.font = .systemFont(ofSize: 15)
        view.textColor = .textColor
        view.textContainerInset = NSSize(width: 24, height: 24)
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.setAccessibilityIdentifier("note.text")
        Task { @MainActor [weak view, weak editor] in
            await Task.yield()
            guard let view else { return }
            view.window?.makeFirstResponder(view)
            editor?.undoManager = view.undoManager
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        view.isEditable = !editor.showChanges
        if editor.showChanges {
            view.undoManager?.disableUndoRegistration()
            view.textStorage?.setAttributedString(changesText())
            view.undoManager?.enableUndoRegistration()
            context.coordinator.showingChanges = true
            context.coordinator.highlight(nil, in: view)
            return
        }
        if context.coordinator.showingChanges {
            view.undoManager?.disableUndoRegistration()
            view.textStorage?.setAttributedString(NSAttributedString(string: editor.text,
                attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]))
            view.undoManager?.enableUndoRegistration()
            context.coordinator.showingChanges = false
        }
        if view.string != editor.text {
            view.undoManager?.disableUndoRegistration()
            view.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (view.string as NSString).length), with: editor.text)
            view.undoManager?.enableUndoRegistration()
        }
        if view.selectedRange() != editor.selection { view.setSelectedRange(editor.selection) }
        let all = NSRange(location: 0, length: (view.string as NSString).length)
        view.textStorage?.addAttributes([.foregroundColor: NSColor.textColor, .font: NSFont.systemFont(ofSize: 15)], range: all)
        view.layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        if let range = editor.busyRange, NSMaxRange(range) <= all.length {
            view.layoutManager?.addTemporaryAttribute(.foregroundColor,
                value: NSColor.textColor.withAlphaComponent(0.5), forCharacterRange: range)
        }
        context.coordinator.highlight(editor.refineHighlight, target: editor.targetHighlightRange, in: view)
        editor.undoManager = view.undoManager
    }

    private func changesText() -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for segment in editor.changes {
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]
            switch segment.kind {
            case .unchanged, .gap: break
            case .inserted: attributes[.backgroundColor] = NSColor(Brand.amber).withAlphaComponent(0.28)
            case .removed:
                attributes[.foregroundColor] = NSColor.textColor.withAlphaComponent(0.5)
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        return result
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let view = scroll.documentView as? NSTextView { coordinator.highlight(nil, in: view) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let editor: NoteEditor
        private let noteUndoManager = UndoManager()
        var updating = false
        var showingChanges = false
        private var targetRange: NSRange?
        private var highlightID: UUID?
        private var highlightTask: Task<Void, Never>?

        func highlight(_ highlight: NoteEditor.RefineHighlight?, target: NSRange? = nil, in view: NSTextView) {
            guard highlightID != highlight?.id || targetRange != target else { return }
            highlightTask?.cancel()
            highlightID = highlight?.id
            targetRange = target
            let all = NSRange(location: 0, length: (view.string as NSString).length)
            view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            if highlight == nil, let target, NSMaxRange(target) <= all.length {
                view.layoutManager?.addTemporaryAttribute(.backgroundColor,
                    value: NSColor(Brand.amber).withAlphaComponent(0.28), forCharacterRange: target)
                return
            }
            guard let highlight, NSMaxRange(highlight.range) <= all.length else { return }
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            func paint(_ opacity: Double) {
                view.layoutManager?.addTemporaryAttribute(.backgroundColor,
                    value: NSColor(Brand.amber).withAlphaComponent(opacity * 0.28), forCharacterRange: highlight.range)
            }
            paint(1)
            highlightTask = Task { @MainActor [weak view] in
                try? await Task.sleep(for: .seconds(reduced ? 1.8 : 1.2))
                guard !Task.isCancelled, let view else { return }
                if !reduced {
                    let start = ContinuousClock.now
                    while !Task.isCancelled {
                        let elapsed = start.duration(to: .now)
                        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                        if seconds >= 0.6 { break }
                        view.layoutManager?.addTemporaryAttribute(.backgroundColor,
                            value: NSColor(Brand.amber).withAlphaComponent(0.28 * (1 - seconds / 0.6)),
                            forCharacterRange: highlight.range)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
                guard !Task.isCancelled else { return }
                view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: highlight.range)
            }
        }
        init(editor: NoteEditor) { self.editor = editor }
        func undoManager(for view: NSTextView) -> UndoManager? { noteUndoManager }
        func textDidChange(_ notification: Notification) {
            guard !updating, !editor.showChanges, let view = notification.object as? NSTextView else { return }
            highlight(nil, in: view)
            editor.text = view.string
            editor.selection = view.selectedRange()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, !editor.showChanges, let view = notification.object as? NSTextView else { return }
            if editor.selection != view.selectedRange() { highlight(nil, in: view) }
            editor.selection = view.selectedRange()
        }
    }
}

/// AppKit's inactive selection otherwise obscures temporary backgrounds. Repainting only
/// decorated selected glyphs preserves native selection and keeps styling out of storage.
private final class RefineTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let manager = layoutManager, let container = textContainer, let storage = textStorage else { return }
        let selected = selectedRange()
        guard selected.length > 0, NSMaxRange(selected) <= storage.length else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        var location = selected.location
        while location < NSMaxRange(selected) {
            var effective = NSRange()
            let color = manager.temporaryAttribute(.backgroundColor, atCharacterIndex: location, effectiveRange: &effective) as? NSColor
            guard effective.location != NSNotFound, effective.length > 0 else { break }
            let range = NSIntersectionRange(effective, selected)
            if let color, range.length > 0 {
                let visible = dirtyRect.intersection(visibleRect).offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
                let visibleGlyphs = manager.glyphRange(forBoundingRect: visible, in: container)
                let glyphs = NSIntersectionRange(manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), visibleGlyphs)
                manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                    let rect = rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                    self.backgroundColor.setFill()
                    rect.fill()
                    color.setFill()
                    rect.fill()
                }
                manager.drawGlyphs(forGlyphRange: glyphs, at: textContainerOrigin)
            }
            location = NSMaxRange(effective)
        }
    }
}
