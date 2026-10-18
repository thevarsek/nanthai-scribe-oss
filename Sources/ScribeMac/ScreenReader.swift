import ApplicationServices
import Foundation
import ScribeCore

/// AX objects stay entirely on the detached reader. Only value snapshots cross back to
/// the dictation session; slow or inaccessible applications cannot hold up recording.
enum ScreenReader {
    struct Snapshot: Sendable {
        var text = ""
        var nearCursor: String?
        var cursorOffset: Int?
    }

    static func read(processIdentifier: pid_t) async -> Snapshot {
        let work = Task.detached(priority: .userInitiated) { readWindow(processIdentifier: processIdentifier) }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private static func readWindow(processIdentifier: pid_t) -> Snapshot {
        let clock = ContinuousClock()
        // Leave a little room for local copying and returning the snapshot. Each IPC
        // inherits only the remaining budget, rather than AX's multi-second default.
        let deadline = clock.now.advanced(by: .milliseconds(140))
        var snapshot = Snapshot()
        let app = AXUIElementCreateApplication(processIdentifier)
        func remaining() -> Float {
            guard !Task.isCancelled else { return 0 }
            let duration = clock.now.duration(to: deadline)
            return max(0, Float(duration.components.seconds) + Float(duration.components.attoseconds) / 1e18)
        }
        func prepare(_ element: AXUIElement) -> Bool {
            let seconds = remaining()
            guard seconds > 0 else { return false }
            return AXUIElementSetMessagingTimeout(element, seconds) == .success
        }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard prepare(element) else { return nil }
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
            return result
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        func safe(_ element: AXUIElement) -> Bool {
            // If the role can't be established, don't ask for any content.
            guard let role = attribute(element, kAXRoleAttribute) as? String else { return false }
            let subrole = attribute(element, kAXSubroleAttribute) as? String
            return role != "AXSecureTextField" && subrole != "AXSecureTextField"
                && (attribute(element, "AXProtectedContent") as? Bool != true)
        }
        guard let window = element(attribute(app, kAXFocusedWindowAttribute)) else { return snapshot }
        if let field = element(attribute(app, kAXFocusedUIElementAttribute)), safe(field),
           let rangeValue = attribute(field, kAXSelectedTextRangeAttribute),
           CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var selection = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection), selection.location >= 0 {
                let length = (attribute(field, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
                let start = max(0, selection.location - 6_000)
                if let length, selection.location <= length {
                    var range = CFRange(location: start, length: min(length - start, selection.location - start + 6_000))
                    if let query = AXValueCreate(.cfRange, &range), prepare(field) {
                        var result: CFTypeRef?
                        if AXUIElementCopyParameterizedAttributeValue(field, kAXStringForRangeParameterizedAttribute as CFString,
                                                                     query, &result) == .success, let text = result as? String {
                            let before = String(decoding: text.utf16.prefix(selection.location - start), as: UTF16.self)
                            snapshot.nearCursor = ScreenTerms.nearCursor(in: text, offset: before.count)
                            snapshot.cursorOffset = min(1_500, before.count)
                        }
                    }
                }
                if snapshot.nearCursor == nil, let text = attribute(field, kAXValueAttribute) as? String {
                    let ns = text as NSString
                    let cursor = min(selection.location, ns.length)
                    let start = max(0, cursor - 6_000)
                    let local = ns.substring(with: NSRange(location: start, length: min(ns.length - start, cursor - start + 6_000)))
                    let before = String(decoding: local.utf16.prefix(cursor - start), as: UTF16.self)
                    snapshot.nearCursor = ScreenTerms.nearCursor(in: local, offset: before.count)
                    snapshot.cursorOffset = min(1_500, before.count)
                }
            }
        }
        var stack: [(AXUIElement, Int)] = [(window, 0)]
        var seen = Set<AXUIElement>()
        var seenText = Set<String>()
        var count = 0
        var visited = 0
        while let (node, depth) = stack.popLast(), remaining() > 0, count < 40_000, visited < 512 {
            guard seen.insert(node).inserted else { continue }
            visited += 1
            guard safe(node) else { continue }
            // Containers can expose a complete document as AXValue, while their leaves
            // expose individual strings. Deduplicate exact copies, preserving order.
            for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                guard remaining() > 0, count < 40_000 else { break }
                if let value = attribute(node, name) as? String, !value.isEmpty {
                    let ns = value as NSString
                    let bounded = String(ns.substring(to: min(ns.length, 80_000)).prefix(40_000 - count))
                    guard seenText.insert(bounded).inserted else { continue }
                    let separator = snapshot.text.isEmpty ? "" : "\n"
                    let part = String((separator + bounded).prefix(40_000 - count))
                    snapshot.text += part
                    count += part.count
                }
            }
            guard depth < 14, prepare(node) else { continue }
            var children: CFArray?
            // Copy only a bounded slice, not an unbounded AXChildren array.
            if AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0, 64, &children) == .success,
               let children = children as? [AXUIElement] {
                for child in children.reversed() { stack.append((child, depth + 1)) }
            }
        }
        return snapshot
    }
}
