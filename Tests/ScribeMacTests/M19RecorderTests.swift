import AppKit
import CoreGraphics
import Carbon.HIToolbox
import Testing
import ScribeMacCore
@testable import ScribeMac

@MainActor
@Suite struct M19RecorderTests {
    private func event(_ type: NSEvent.EventType, code: UInt16, flags: NSEvent.ModifierFlags = [], characters: String = "") throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @Test func rejectedAndConflictStayOpenThenAcceptOnRelease() throws {
        let capture = ShortcutCapture()
        var saved: TalkShortcut?
        let finish: (TalkShortcut?) -> Void = { saved = $0 }
        capture.handle(try event(.keyDown, code: 0, characters: "a"), finish: finish)
        #expect(capture.validation == .rejected)
        #expect(capture.caps == ["A"])
        #expect(saved == nil)
        capture.handle(try event(.keyDown, code: 49, flags: .command, characters: " "), finish: finish)
        #expect(capture.validation == .conflict)
        capture.handle(try event(.keyUp, code: 49, flags: .command), finish: finish)
        #expect(saved == nil)
        capture.handle(try event(.keyDown, code: 49, flags: [.control, .option], characters: " "), finish: finish)
        #expect(capture.caps == ["⌃", "⌥", "Space"])
        #expect(capture.validation == .accepted)
        #expect(saved == nil)
        capture.handle(try event(.keyUp, code: 49), finish: finish)
        #expect(saved == .controlOptionSpace)
    }
}

extension M19RecorderTests {
    @Test(arguments: TalkKey.allCases) func loneModifiersCommitOnRelease(key: TalkKey) throws {
        let capture = ShortcutCapture()
        var saved: TalkShortcut?
        let cg = try #require(CGEvent(keyboardEventSource: nil, virtualKey: UInt16(key.keyCode), keyDown: true))
        cg.type = .flagsChanged
        let generic: CGEventFlags = key == .rightOption ? .maskAlternate : key == .rightCommand ? .maskCommand : key == .rightControl ? .maskControl : .maskSecondaryFn
        cg.flags = [key.flag, generic]
        capture.handle(try #require(NSEvent(cgEvent: cg))) { saved = $0 }
        #expect(capture.caps == [key.shortcutTitle])
        #expect(saved == nil)
        cg.flags = []
        capture.handle(try #require(NSEvent(cgEvent: cg))) { saved = $0 }
        #expect(saved == .modifier(key))
    }

    @Test func escapeCancels() throws {
        let capture = ShortcutCapture()
        var cancelled = false
        capture.handle(try event(.keyDown, code: UInt16(kVK_Escape))) { cancelled = $0 == nil }
        #expect(cancelled)
    }
}

extension M19RecorderTests {
    @Test func activeTapCapturesSystemConflictAndKeepsFnObserved() throws {
        let tap = PushToTalk()
        let capture = ShortcutCapture()
        var actions: [DictationShortcuts.Action] = []
        tap.onChange = { _, action in if let action { actions.append(action) } }
        tap.isRecordingShortcut = true
        tap.recordEvent = { event in
            if let event = NSEvent(cgEvent: event) { capture.handle(event) { _ in } }
        }
        let space = try #require(CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_Space), keyDown: true))
        space.flags = .maskCommand
        #expect(tap.handle(space, type: .keyDown))
        #expect(capture.validation == .conflict)
        let fn = try #require(CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_Function), keyDown: true))
        fn.type = .flagsChanged
        fn.flags = .maskSecondaryFn
        #expect(!tap.handle(fn, type: .flagsChanged))
        #expect(actions.isEmpty)
    }
}

extension M19RecorderTests {
    @Test func modifiedEscapeCanBeRecorded() throws {
        let capture = ShortcutCapture()
        var saved: TalkShortcut?
        capture.handle(try event(.keyDown, code: UInt16(kVK_Escape), flags: .command)) { saved = $0 }
        #expect(capture.validation == .accepted)
        #expect(capture.caps == ["⌘", "Esc"])
        capture.handle(try event(.keyUp, code: UInt16(kVK_Escape))) { saved = $0 }
        #expect(saved == .key(code: UInt16(kVK_Escape), modifiers: .command, label: "Esc"))
    }
}
