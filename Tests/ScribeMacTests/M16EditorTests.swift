import AppKit
import ScribeCore
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized)
struct M16EditorTests {
    @Test func nativeTypingAndPresetUndoShareOneDocumentStack() async throws {
        _ = NSApplication.shared
        let editor = NoteEditor(note: Note(text: "Hello"))
        let host = NSHostingController(rootView: MacNoteTextEditor(editor: editor).frame(width: 600, height: 300))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        defer { window.close() }
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let textView = try #require(findTextView(host.view))
        window.makeFirstResponder(textView)
        textView.insertText(" world", replacementRange: textView.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        #expect(editor.text == "Hello world")
        await editor.apply(.shorter, rewriter: MacNativeUndoRewriter())
        try await Task.sleep(for: .milliseconds(100))
        #expect(textView.string == "Hi")
        #expect(editor.refineHighlight != nil)
        #expect(textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil)
        #expect(textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)

        editor.showChanges = true
        try await Task.sleep(for: .milliseconds(60))
        #expect(!textView.isEditable)
        #expect(editor.text == "Hi")
        editor.showChanges = false
        try await Task.sleep(for: .milliseconds(60))
        #expect(textView.isEditable)
        #expect(textView.string == "Hi")
        #expect(textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(100))
        #expect(textView.string == "Hello world")
        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(100))
        #expect(editor.text == "Hello")
        textView.undoManager?.redo()
        try await Task.sleep(for: .milliseconds(100))
        #expect(editor.text == "Hello world")
    }
    private func findTextView(_ view: NSView) -> NSTextView? {
        if let view = view as? NSTextView { return view }
        return view.subviews.lazy.compactMap { findTextView($0) }.first
    }
}

private struct MacNativeUndoRewriter: TextRewriter {
    let id = "native-undo"
    func isAvailable() async -> Bool { true }
    func rewrite(_ request: RewriteRequest) async throws -> String { "Hi" }
}
