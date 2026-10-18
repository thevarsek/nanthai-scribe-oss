import AppKit
import Carbon.HIToolbox
import ScribeMacCore

// Hardware mapping stays in the app; the persisted choice lives in ScribeMacCore.
extension TalkKey {
    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)
        case .rightCommand: Int64(kVK_RightCommand)
        case .rightControl: Int64(kVK_RightControl)
        case .fn: Int64(kVK_Function)
        }
    }

    /// Device-specific flag bits (IOKit `NX_DEVICER*KEYMASK`). The public `.maskAlternate`
    /// is set by *either* Option key, so holding Left ⌥ would hide a Right ⌥ release.
    var flag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)
        case .rightCommand: CGEventFlags(rawValue: 0x10)
        case .rightControl: CGEventFlags(rawValue: 0x2000)
        case .fn: .maskSecondaryFn
        }
    }

    var modifiers: TalkShortcut.Modifiers {
        switch self {
        case .rightOption: .option
        case .rightCommand: .command
        case .rightControl: .control
        case .fn: []
        }
    }

    /// fn drives fn+arrows and the emoji picker, so it's observed but never swallowed.
    var swallows: Bool { self != .fn }
}

/// Matches the chosen Talk shortcut via a session event tap. Requires Accessibility —
/// `NSEvent` global monitors can't tell left from right modifiers or see fn.
@MainActor
final class PushToTalk {
    var shortcut: TalkShortcut = .rightOption
    var recordEvent: ((CGEvent) -> Void)?
    var isRecordingShortcut = false {
        didSet {
            if oldValue, !isRecordingShortcut {
                shortcuts = DictationShortcuts()
                heldMainKey = nil
                comboDown = false
            }
        }
    }
    var key: TalkKey {
        get { if case .modifier(let key) = shortcut { key } else { .rightOption } }
        set { shortcut = .modifier(newValue) }
    }
    private var heldMainKey: UInt16?
    private var comboDown = false
    var onChange: ((DictationShortcuts, DictationShortcuts.Action?) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var shortcuts = DictationShortcuts()

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        stop()
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) {
                $0 | (1 << $1.rawValue)
            },
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<PushToTalk>.fromOpaque(refcon).takeUnretainedValue()
                // The tap is on the main run loop, so this really is the main thread.
                let swallow = MainActor.assumeIsolated {
                    monitor.handle(event, type: type)
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        shortcuts = DictationShortcuts()
        heldMainKey = nil
        comboDown = false
    }

    func complete() {
        shortcuts.complete()
        onChange?(shortcuts, nil)
    }

    func handle(_ event: CGEvent, type: CGEventType) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if (type == .flagsChanged || type == .keyDown || type == .keyUp), let recordEvent {
            recordEvent(event)
            return code != Int64(kVK_Function)
        }
        return handle(type: type, keyCode: code, flags: event.flags)
    }

    func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        // macOS disables taps that stall or get interrupted; turn it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard !isRecordingShortcut else { return false }
        let input: DictationShortcuts.Event
        var swallowTalk = false
        let modifiers = TalkShortcut.Modifiers(flags)
        switch shortcut {
        case .modifier(let key):
            if type == .flagsChanged {
                let command = key == .rightCommand
                    ? flags.contains(CGEventFlags(rawValue: 0x08))
                    : flags.contains(.maskCommand)
                if keyCode == key.keyCode {
                    input = .talk(down: flags.contains(key.flag), shift: flags.contains(.maskShift), command: command)
                    swallowTalk = key.swallows
                } else {
                    input = .modifiers(shift: flags.contains(.maskShift), command: command)
                }
            } else if let special = specialKey(type: type, keyCode: keyCode) {
                input = special
            } else { return false }
        case .key(let code, let required, _):
            let lateShift = type == .flagsChanged &&
                ((keyCode == Int64(kVK_Shift) && flags.rawValue & 0x02 != 0) ||
                 (keyCode == Int64(kVK_RightShift) && flags.rawValue & 0x04 != 0))
            let lateCommand = type == .flagsChanged &&
                ((keyCode == Int64(kVK_Command) && flags.rawValue & 0x08 != 0) ||
                 (keyCode == Int64(kVK_RightCommand) && flags.rawValue & 0x10 != 0))
            let shift = modifiers.contains(.shift) && (!required.contains(.shift) || lateShift)
            let command = modifiers.contains(.command) && (!required.contains(.command) || lateCommand)
            if type == .keyDown, keyCode == Int64(code) {
                if heldMainKey != nil { return true } // Consume autorepeat without restarting.
                if modifiers.isSuperset(of: required),
                   modifiers.intersection([.control, .option]).subtracting(required).isEmpty {
                    heldMainKey = code
                    comboDown = true
                    input = .talk(down: true, shift: shift, command: command)
                    swallowTalk = true
                } else if let special = specialKey(type: type, keyCode: keyCode) {
                    input = special
                } else { return false }
            } else if type == .keyUp, let heldMainKey, Int64(heldMainKey) == keyCode {
                self.heldMainKey = nil
                comboDown = false
                input = .talk(down: false, shift: shift, command: command)
                swallowTalk = true
            } else if type == .flagsChanged {
                if comboDown, !modifiers.isSuperset(of: required) {
                    comboDown = false
                    input = .talk(down: false, shift: shift, command: command)
                } else {
                    input = .modifiers(shift: shift, command: command)
                }
            } else if let special = specialKey(type: type, keyCode: keyCode) {
                input = special
            } else { return false }
        }

        let old = shortcuts
        let result = shortcuts.handle(input)
        if old != shortcuts || result.action != nil { onChange?(shortcuts, result.action) }
        return swallowTalk || result.swallow
    }
    private func specialKey(type: CGEventType, keyCode: Int64) -> DictationShortcuts.Event? {
        guard type == .keyDown || type == .keyUp else { return nil }
        let key: DictationShortcuts.Key
        switch Int(keyCode) {
        case kVK_Return: key = .return
        case kVK_ANSI_KeypadEnter: key = .keypadEnter
        case kVK_Escape: key = .escape
        default: return nil
        }
        return .key(key, down: type == .keyDown)
    }

}

extension TalkShortcut.Modifiers {
    init(_ flags: CGEventFlags) {
        self = []
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskCommand) { insert(.command) }
        if flags.contains(.maskShift) { insert(.shift) }
    }
}
