import AppKit
import ApplicationServices
import Foundation
import ScribeCore
import Testing
@testable import ScribeMac

@MainActor
@Suite struct M9MacLearningTests {
    @Test func valueOnlyAXFieldsResolveUniqueNewInsertions() {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let target = AXCorrectionWatch.Target(element: element, inserted: "Nantai", previousValue: "Ask  today", startedAt: .now)
        let span = target.resolved(in: "Ask Nantai today")
        #expect(span?.prefix == "Ask ")
        #expect(span?.suffix == " today")
        #expect(span?.current(in: "Ask NanthAi today", at: .now) == "NanthAi")
        #expect(target.resolved(in: "Ask  today") == nil)
        #expect(target.resolved(in: "Nantai and Nantai") == nil)
        #expect(target.resolved(in: "Missing insertion") == nil)
    }

    @Test func hudAddAndDeferralDoNotTakeFocus() throws {
        let suite = "M9Mac-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        let pair = CorrectionPair(heard: "Nantai", meant: "NanthAi")
        #expect(dictation.learning.record(pair, canAsk: true))
        dictation.previewCorrection(pair)
        _ = NSApplication.shared
        let panel = HUDController.makePanel(dictation: dictation)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.ignoresMouseEvents)
        dictation.dismissCorrection()
        #expect(dictation.correctionPrompt == nil)
        #expect(dictation.learning.document.corrections.entries[0].deferrals == 1)
        dictation.previewCorrection(pair)
        dictation.addCorrection()
        #expect(dictation.dictionary.first?.source == .learned)
        #expect(dictation.dictionary.first?.variants == ["Nantai"])
        #expect(dictation.correctionAdded)
        #expect(dictation.learning.document.corrections.entries.isEmpty)
        dictation.previewCorrection(nil)
    }

    /// Turning the option off drops the loaded names at once and persists "off".
    @Test func contactsOffIsOff() throws {
        let suite = "M9MacContacts-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let contacts = ContactsNames(defaults: defaults)
        #expect(!contacts.enabled)
        contacts.previewEnabled(true, names: ["John", "Andy"])
        #expect(contacts.matches(in: "ask jon", languages: ["en_US"]).map(\.term) == ["John"])
        contacts.setEnabled(false)
        #expect(!contacts.enabled && contacts.names.isEmpty)
        #expect(defaults.object(forKey: "useContactNames") as? Bool == false)
        #expect(contacts.matches(in: "ask jon", languages: ["en_US"]).isEmpty)
        contacts.refresh()
        #expect(contacts.names.isEmpty)
    }

    /// The owner's pairs against the real macOS dictionaries, English and Italian.
    @Test func contactsNeverReplaceOrdinaryWords() {
        let contacts = ContactsNames(defaults: UserDefaults(suiteName: "M9MacWords-\(UUID())")!)
        contacts.previewEnabled(true, names: ["Andy", "Mara", "Dave", "Jake", "Linsey", "Donna", "Farah", "Alain", "Falso", "Ally",
                                              "Giulia", "Shawn", "Niccolò"])
        let english = "I have to make more lines and also really get it done again so far. And all of it"
        #expect(contacts.matches(in: english, languages: ["en_US", "it_IT"]).isEmpty)
        #expect(contacts.matches(in: "ho fatto anche le linee e poi basta", languages: ["it_IT"]).isEmpty)
        #expect(Set(contacts.matches(in: "I called sean and julia", languages: ["en_US"]).map(\.term)) == ["Shawn", "Giulia"])
        #expect(contacts.matches(in: "ho sentito nicolo ieri", languages: ["it_IT"]).map(\.term) == ["Niccolò"])
        #expect(ContactsNames.spellLanguages(for: ["en_US", "it-IT", "xx_YY"], available: ["it", "en_GB", "en"]) == ["en", "it"])
    }
}
