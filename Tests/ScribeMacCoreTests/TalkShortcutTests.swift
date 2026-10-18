import Foundation
import Testing
@testable import ScribeMacCore

@Suite struct TalkShortcutTests {
    @Test func choicesRoundTripAndMigrate() throws {
        let domain = "M19-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        for key in TalkKey.allCases {
            defaults.removeObject(forKey: "talkShortcut")
            defaults.set(key.rawValue, forKey: "talkKey")
            let settings = MacSettings(defaults: defaults)
            #expect(settings.talkShortcut == .modifier(key))
            #expect(defaults.object(forKey: "talkKey") == nil)
        }
        let settings = MacSettings(defaults: defaults)
        for shortcut in TalkShortcut.presets + [.rightControl, .key(code: 0, modifiers: [.command, .shift], label: "A")] {
            #expect(try JSONDecoder().decode(TalkShortcut.self, from: JSONEncoder().encode(shortcut)) == shortcut)
            settings.talkShortcut = shortcut
            #expect(MacSettings(defaults: defaults).talkShortcut == shortcut)
        }
        defaults.set("rightCommand", forKey: "talkKey")
        #expect(MacSettings(defaults: defaults).talkShortcut == settings.talkShortcut)
    }

    @Test func acceptedAndRejectedKeys() {
        for code in TalkShortcut.functionKeyCodes {
            #expect(TalkShortcut.key(code: code, modifiers: [], label: "F").validation == .accepted)
        }
        for code: UInt16 in [0, 18, 49, 48, 36] {
            #expect(TalkShortcut.key(code: code, modifiers: [], label: "key").validation == .rejected)
            #expect(TalkShortcut.key(code: code, modifiers: [.shift], label: "key").validation == .rejected)
            #expect(TalkShortcut.key(code: code, modifiers: [.control, .option], label: "key").validation == .accepted)
        }
        #expect(TalkShortcut.Validation.rejected.message == "Add ⌃, ⌥ or ⌘")
        #expect(TalkShortcut.Validation.conflict.message == "That shortcut is used by macOS.")
        #expect(TalkShortcut.controlOptionSpace.keyCaps == ["⌃", "⌥", "Space"])
    }

    @Test func commonSystemConflicts() {
        for shortcut in [TalkShortcut.key(code: 49, modifiers: .command, label: "Space"),
                         .key(code: 48, modifiers: .command, label: "Tab"),
                         .key(code: 49, modifiers: .control, label: "Space"),
                         .key(code: 20, modifiers: [.command, .shift], label: "3")] {
            #expect(shortcut.validation == .conflict)
        }
    }

    @Test func invalidPersistedDataRecovers() throws {
        let domain = "M19-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(Data("broken".utf8), forKey: "talkShortcut")
        #expect(MacSettings(defaults: defaults).talkShortcut == .rightOption)
        let invalid = TalkShortcut.key(code: 0, modifiers: [], label: "A")
        defaults.set(try JSONEncoder().encode(invalid), forKey: "talkShortcut")
        #expect(MacSettings(defaults: defaults).talkShortcut == .rightOption)
    }
}
