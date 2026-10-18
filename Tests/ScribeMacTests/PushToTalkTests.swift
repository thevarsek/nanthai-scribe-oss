import CoreGraphics
import Carbon.HIToolbox
import Testing
import ScribeMacCore
@testable import ScribeMac

@MainActor
@Suite struct PushToTalkTests {
    @Test func defaultTalkKeyAndUnrelatedModifiers() {
        let tap = PushToTalk()
        var actions: [DictationShortcuts.Action] = []
        tap.onChange = { _, action in if let action { actions.append(action) } }
        #expect(!tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Option), flags: .maskAlternate))
        #expect(actions.isEmpty)
        #expect(tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightOption), flags: [.maskAlternate, TalkKey.rightOption.flag]))
        // Left Option remains down while Right Option releases: device flag wins.
        #expect(tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightOption), flags: .maskAlternate))
        #expect(actions == [.start, .finish])
    }

    @Test func rightCommandDoesNotPolishItselfButLeftCommandDoes() {
        for leftCommand in [false, true] {
            let tap = PushToTalk()
            tap.key = .rightCommand
            var latest = DictationShortcuts()
            tap.onChange = { state, _ in latest = state }
            var flags: CGEventFlags = [.maskCommand, TalkKey.rightCommand.flag]
            if leftCommand { flags.insert(CGEventFlags(rawValue: 0x08)) }
            #expect(tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightCommand), flags: flags))
            #expect(latest.polish == leftCommand)
        }
    }

    @Test func lateCommandWithRightCommandTalkKey() {
        let tap = PushToTalk()
        tap.key = .rightCommand
        var latest = DictationShortcuts()
        tap.onChange = { state, _ in latest = state }
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightCommand), flags: [.maskCommand, TalkKey.rightCommand.flag])
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Command), flags: [.maskCommand, TalkKey.rightCommand.flag, CGEventFlags(rawValue: 0x08)])
        #expect(latest.polish)
    }

    @Test func fnIsObservedWithoutSwallowing() {
        let tap = PushToTalk()
        tap.key = .fn
        var actions: [DictationShortcuts.Action] = []
        tap.onChange = { _, action in if let action { actions.append(action) } }
        #expect(!tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: .maskSecondaryFn))
        #expect(!tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Function), flags: []))
        #expect(actions == [.start, .finish])
    }

    @Test(arguments: [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape])
    func specialKeyPairsAreConsumedOnlyForHandsFree(_ keyCode: Int) {
        let tap = PushToTalk()
        let code = Int64(keyCode)
        #expect(!tap.handle(type: .keyDown, keyCode: code, flags: []))
        #expect(!tap.handle(type: .keyUp, keyCode: code, flags: []))
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightOption), flags: [TalkKey.rightOption.flag, .maskAlternate])
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_Shift), flags: [TalkKey.rightOption.flag, .maskAlternate, .maskShift])
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightOption), flags: .maskShift)
        #expect(!tap.handle(type: .keyDown, keyCode: Int64(kVK_ANSI_A), flags: []))
        #expect(tap.handle(type: .keyDown, keyCode: code, flags: []))
        tap.complete()
        #expect(tap.handle(type: .keyUp, keyCode: code, flags: []))
        #expect(!tap.handle(type: .keyDown, keyCode: code, flags: []))
    }

    @Test func aNormalHoldLeavesReturnAndEscapeUntouched() {
        let tap = PushToTalk()
        _ = tap.handle(type: .flagsChanged, keyCode: Int64(kVK_RightOption), flags: TalkKey.rightOption.flag)
        for code in [kVK_Return, kVK_Escape] {
            #expect(!tap.handle(type: .keyDown, keyCode: Int64(code), flags: []))
            #expect(!tap.handle(type: .keyUp, keyCode: Int64(code), flags: []))
        }
    }
}
