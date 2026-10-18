import AppKit
import ApplicationServices
import ScribeCore

/// Types text into whichever app has focus by pasting it.
///
/// Paste is the one path that works everywhere — native fields, Electron apps, browsers,
/// terminals. Direct Accessibility writes report success in Electron apps while inserting
/// nothing. The user's clipboard is restored afterwards.
@MainActor
enum TextInserter {
    static func insert(_ text: String, replacingSelection: Bool = false) {
        guard !text.isEmpty else { return }
        let text = !replacingSelection && Spacing.needsLeadingSpace(before: characterBeforeCursor(), inserting: text) ? " " + text : text
        remember(text)

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChange = pasteboard.changeCount

        sendCommandV()

        // Give the target app time to read the pasteboard before putting the old one back.
        // Skip the restore if anything else wrote to the clipboard meanwhile.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard pasteboard.changeCount == ourChange else { return }
            restore(saved, to: pasteboard)
        }
    }

    // MARK: - What's before the cursor

    struct Context {
        var selection: String?
        var draftBefore: String?
        var appName: String?
        var bundleID: String?
    }

    /// Capture at the start, before the user speaks or changes the selection.
    static func context(app capturedApp: Context? = nil) -> Context {
        let app = NSWorkspace.shared.frontmostApplication
        var context = capturedApp ?? Context(appName: app?.localizedName, bundleID: app?.bundleIdentifier)
        guard let field = focusedField() else { return context }
        var selected: AnyObject?
        if AXUIElementCopyAttributeValue(field, kAXSelectedTextAttribute as CFString, &selected) == .success,
           let text = selected as? String, !text.isEmpty {
            context.selection = text
        }
        if let selection = selectedRange(in: field), selection.location > 0 {
            // AX offsets are UTF-16. Trim by Character after reading to respect emoji
            // and composed letters, and never send more than 600 characters.
            let count = min(selection.location, 1_200)
            let range = CFRange(location: selection.location - count, length: count)
            context.draftBefore = string(in: field, range: range).map { String($0.suffix(600)) }
        }
        return context
    }

    /// Last insertion, for apps that don't expose their text (Electron, some web views).
    private static var last: (app: pid_t, date: Date, endsWithNewline: Bool)?

    private static func remember(_ text: String) {
        guard let app = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        last = (app, .now, text.last?.isNewline ?? false)
    }

    /// The character before the insertion point, nil at the start of a field.
    private static func characterBeforeCursor() -> Character? {
        switch readBeforeCursor() {
        case .start: return nil
        case .after(let character): return character
        case .unknown: break
        }
        // Accessibility couldn't tell us. If we pasted into this same app moments ago,
        // assume the cursor is still right after that text.
        guard let last,
              last.app == NSWorkspace.shared.frontmostApplication?.processIdentifier,
              Date.now.timeIntervalSince(last.date) < 120
        else { return nil }
        return last.endsWithNewline ? "\n" : "."
    }

    private enum BeforeCursor { case start, after(Character), unknown }

    /// Reads via Accessibility; `.unknown` when the app doesn't expose its text.
    private static func readBeforeCursor() -> BeforeCursor {
        guard let field = focusedField(), let selection = selectedRange(in: field) else { return .unknown }
        if selection.location <= 0 { return .start }
        let previous = CFRange(location: selection.location - 1, length: 1)
        guard let character = string(in: field, range: previous)?.last else { return .unknown }
        return .after(character)
    }

    private static func focusedField() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }
        return (element as! AXUIElement)
    }

    private static func selectedRange(in field: AXUIElement) -> CFRange? {
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection),
              selection.location >= 0, selection.length >= 0 else { return nil }
        return selection
    }

    private static func string(in field: AXUIElement, range: CFRange) -> String? {
        var range = range
        guard let query = AXValueCreate(.cfRange, &range) else { return nil }
        var result: AnyObject?
        if AXUIElementCopyParameterizedAttributeValue(field, kAXStringForRangeParameterizedAttribute as CFString, query, &result) == .success,
           let text = result as? String { return text }
        // Some native fields expose their value but not the parameterized attribute.
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        let utf16 = text.utf16
        guard range.location <= utf16.count, range.length <= utf16.count - range.location else { return nil }
        return String(decoding: utf16.dropFirst(range.location).prefix(range.length), as: UTF16.self)
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(9) // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        })
    }
}
