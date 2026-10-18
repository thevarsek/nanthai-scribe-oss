import AppKit
import ApplicationServices
import ScribeCore

/// The observer watches the original field, never whichever app later gains focus.
@MainActor
final class AXCorrectionWatch {
    struct Target {
        let element: AXUIElement
        var span: CorrectionSpan?
        let inserted: String
        let previousValue: String
        let startedAt: Date

        /// Some host fields expose their value but no AX selection range. Resolve only a
        /// unique new occurrence after the paste, then use the same immutable boundaries.
        func resolved(in value: String) -> CorrectionSpan? {
            if let span { return span }
            guard value != previousValue, !inserted.isEmpty, let range = value.range(of: inserted),
                  value[value.index(after: range.lowerBound)...].range(of: inserted) == nil else { return nil }
            return CorrectionSpan(inserted: inserted, prefix: String(value[..<range.lowerBound]),
                suffix: String(value[range.upperBound...]), at: startedAt)
        }
    }
    var candidate: (CorrectionPair, Bool) -> Void = { _, _ in }
    var dictionary: () -> [DictionaryEntry] = { [] }
    var canAsk: () -> Bool = { false }
    private var observer: AXObserver?
    private var target: Target?
    private var polling: Task<Void, Never>?
    private var stable: Task<Void, Never>?
    private var pending: CorrectionPair?
    private var lastValue: String?
    private var seen = Set<String>()
    private var prompted = false

    static func capture(inserted: String, replacingSelection: Bool) -> Target? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let field = focused as! AXUIElement
        guard let value = value(of: field) else { return nil }
        let fallback = Target(element: field, inserted: inserted, previousValue: value, startedAt: .now)
        var rawRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &rawRange) == .success,
              let rawRange, CFGetTypeID(rawRange) == AXValueGetTypeID() else { return fallback }
        var selection = CFRange()
        guard AXValueGetValue(rawRange as! AXValue, .cfRange, &selection), selection.location >= 0, selection.length >= 0,
              selection.location + selection.length <= (value as NSString).length else { return fallback }
        let prefix = (value as NSString).substring(to: selection.location)
        let suffix = (value as NSString).substring(from: selection.location + selection.length)
        let actual = !replacingSelection && Spacing.needsLeadingSpace(before: prefix.last, inserting: inserted) ? " " + inserted : inserted
        return Target(element: field, span: CorrectionSpan(inserted: actual, prefix: prefix, suffix: suffix),
            inserted: actual, previousValue: value, startedAt: fallback.startedAt)
    }

    func start(_ target: Target) {
        stop()
        self.target = target
        seen = []; prompted = false; lastValue = nil
        var pid: pid_t = 0
        AXUIElementGetPid(target.element, &pid)
        var created: AXObserver?
        if AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            let watcher = Unmanaged<AXCorrectionWatch>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.check() }
        }, &created) == .success, let created,
           AXObserverAddNotification(created, target.element, kAXValueChangedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque()) == .success {
            observer = created
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        // The timer also enforces the lifetime when an observed field stays unchanged.
        polling = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            while !Task.isCancelled {
                guard let self else { return }
                self.check()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func stop() {
        polling?.cancel(); polling = nil
        stable?.cancel(); stable = nil; pending = nil
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; target = nil
    }

    private func check() {
        guard var target, Date.now.timeIntervalSince(target.startedAt) <= 60,
              let value = Self.value(of: target.element) else { stop(); return }
        if target.span == nil {
            // A delayed paste can still arrive on the next tick; an ambiguous changed value cannot.
            if value == target.previousValue { return }
            guard let span = target.resolved(in: value) else { stop(); return }
            target.span = span
            self.target = target
        }
        guard let span = target.span, let current = span.current(in: value, at: .now) else { stop(); return }
        guard value != lastValue else { return }
        lastValue = value
        stable?.cancel(); pending = nil
        guard let pair = CorrectionDetector.candidate(inserted: span.inserted, current: current, dictionary: dictionary()),
              !seen.contains(pair.key) else { return }
        pending = pair
        stable = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, let active = self.target, self.pending == pair,
                  let latest = Self.value(of: active.element), latest == value else { return }
            self.seen.insert(pair.key)
            self.candidate(pair, !self.prompted && self.canAsk())
        }
    }
    func didPrompt() { prompted = true }

    private static func value(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
