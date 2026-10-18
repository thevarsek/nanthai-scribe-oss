import AppKit
import CoreGraphics
import Carbon.HIToolbox
import Testing
import ScribeMacCore
@testable import ScribeMac

@MainActor
@Suite struct M19ShortcutTests {
    @Test(arguments: [false, true]) func comboEndsOnEitherRelease(modifierFirst: Bool) {
        let tap = PushToTalk()
        tap.shortcut = .controlOptionSpace
        var actions: [DictationShortcuts.Action] = []
        tap.onChange = { _, action in if let action { actions.append(action) } }
        #expect(!tap.handle(type: .keyDown, keyCode: 49, flags: .maskControl))
        #expect(!tap.handle(type: .keyUp, keyCode: 49, flags: []))
        #expect(tap.handle(type: .keyDown, keyCode: 49, flags: [.maskControl, .maskAlternate]))
        #expect(tap.handle(type: .keyDown, keyCode: 49, flags: [.maskControl, .maskAlternate]))
        if modifierFirst {
            #expect(!tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Control), flags: .maskAlternate))
            #expect(actions == [.start, .finish])
            _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Control), flags: [.maskControl, .maskAlternate])
            #expect(tap.handle(type: .keyDown, keyCode: 49, flags: [.maskControl, .maskAlternate]))
            #expect(actions == [.start, .finish])
        }
        #expect(tap.handle(type: .keyUp, keyCode: 49, flags: []))
        #expect(actions == [.start, .finish])
    }

    @Test func requiredCommandAndShiftAreNotChords() {
        let tap = PushToTalk()
        tap.shortcut = .key(code: 0, modifiers: [.command, .shift], label: "A")
        var state = DictationShortcuts()
        tap.onChange = { latest, _ in state = latest }
        #expect(tap.handle(type: .keyDown, keyCode: 0, flags: [.maskCommand, .maskShift]))
        #expect(!state.polish)
        #expect(!state.handsFree)
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Command), flags: .maskShift)
        #expect(state.phase == .processing)
        #expect(tap.handle(type: .keyUp, keyCode: 0, flags: []))
    }

    @Test(arguments: TalkShortcut.functionKeyCodes) func functionKeysKeepLateChords(code: UInt16) {
        let tap = PushToTalk()
        tap.shortcut = .key(code: code, modifiers: [], label: "F")
        var state = DictationShortcuts()
        var actions: [DictationShortcuts.Action] = []
        tap.onChange = { latest, action in state = latest; if let action { actions.append(action) } }
        #expect(tap.handle(type: .keyDown, keyCode: Int64(code), flags: .maskSecondaryFn))
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Shift), flags: .maskShift)
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Command), flags: [.maskShift, .maskCommand])
        #expect(state.polish && state.handsFree)
        #expect(tap.handle(type: .keyUp, keyCode: Int64(code), flags: []))
        #expect(state.phase == .listening)
        #expect(tap.handle(type: .keyDown, keyCode: Int64(kVK_Return), flags: []))
        tap.complete()
        #expect(tap.handle(type: .keyUp, keyCode: Int64(kVK_Return), flags: []))
        #expect(actions == [.start, .finish])
    }

    @Test func completionPreservesConsumedComboPair() {
        let tap = PushToTalk()
        tap.shortcut = .f13
        #expect(tap.handle(type: .keyDown, keyCode: 105, flags: []))
        tap.complete()
        #expect(tap.handle(type: .keyDown, keyCode: 105, flags: []))
        #expect(tap.handle(type: .keyUp, keyCode: 105, flags: []))
        #expect(!tap.handle(type: .keyUp, keyCode: 105, flags: []))
    }

    @Test func recordingSuspendsTalk() {
        let tap = PushToTalk()
        tap.isRecordingShortcut = true
        var actions: [DictationShortcuts.Action] = []
        tap.onChange = { _, action in if let action { actions.append(action) } }
        #expect(!tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightOption), flags: TalkKey.rightOption.flag))
        #expect(actions.isEmpty)
    }
}

extension M19ShortcutTests {
    @Test func additionalPhysicalRequiredModifiersStillActAsLateChords() {
        let tap = PushToTalk()
        tap.shortcut = .key(code: 0, modifiers: [.command, .shift], label: "A")
        var state = DictationShortcuts()
        tap.onChange = { latest, _ in state = latest }
        _ = tap.handle(type: .keyDown, keyCode: 0, flags: [.maskCommand, .maskShift, CGEventFlags(rawValue: 0x0A)])
        #expect(!state.polish && !state.handsFree)
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightCommand), flags: [.maskCommand, .maskShift, CGEventFlags(rawValue: 0x1A)])
        #expect(state.polish)
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightShift), flags: [.maskCommand, .maskShift, CGEventFlags(rawValue: 0x1E)])
        #expect(state.handsFree)
        #expect(tap.handle(type: .keyUp, keyCode: 0, flags: [.maskCommand, .maskShift]))
        #expect(state.phase == .listening)
    }
}

extension M19ShortcutTests {
    @Test(arguments: [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape]) func plainSpecialKeyStillWorksWhenItIsAlsoTheComboKey(code: Int) {
        let tap = PushToTalk()
        tap.shortcut = .key(code: UInt16(code), modifiers: .option, label: "key")
        var actions: [DictationShortcuts.Action] = []
        tap.onChange = { _, action in if let action { actions.append(action) } }
        #expect(tap.handle(type: .keyDown, keyCode: Int64(code), flags: .maskAlternate))
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Shift), flags: [.maskAlternate, .maskShift])
        #expect(tap.handle(type: .keyUp, keyCode: Int64(code), flags: []))
        #expect(tap.handle(type: .keyDown, keyCode: Int64(code), flags: []))
        #expect(tap.handle(type: .keyUp, keyCode: Int64(code), flags: []))
        #expect(actions == [.start, code == kVK_Escape ? .cancel : .finish])
    }
}
