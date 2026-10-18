import Foundation
import ScribeCore
import ScribeMacCore
import Testing
@testable import ScribeMac

@MainActor
@Suite struct M2DictationTests {
    @Test func preferencesAreExposedAndPersistedByDictation() throws {
        try withFixture { defaults, url in
            let dictation = Dictation(defaults: defaults, historyURL: url, vocabularyDirectory: url.deletingPathExtension())
            #expect(dictation.useScreenContext)
            #expect(dictation.engine == .apple)
            #expect(dictation.historyRetention == .forever)
            dictation.tone = .formal
            dictation.snippets = [Snippet(trigger: "my signature", text: "Best,\nAlex")]
            dictation.dictionary = [DictionaryEntry(term: "NanthAi", variants: ["nant"])]
            dictation.useScreenContext = false
            dictation.engine = .gemma
            dictation.soundsEnabled = false
            dictation.talkKey = .rightCommand
            let restored = Dictation(defaults: defaults, historyURL: url, vocabularyDirectory: url.deletingPathExtension())
            #expect(restored.tone == .formal)
            #expect(restored.snippets == dictation.snippets)
            #expect(restored.dictionary == dictation.dictionary)
            #expect(defaults.data(forKey: "snippets") == nil)
            #expect(!restored.useScreenContext)
            #expect(restored.engine == .gemma)
            #expect(!restored.soundsEnabled)
            #expect(restored.talkKey == .rightCommand)
            #expect(defaults.object(forKey: "useScreenContext") as? Bool == false)
        }
    }

    @Test func historyPolicyChangesAreAppliedImmediately() throws {
        try withFixture { defaults, url in
            let entries = [DictationEntry(date: .now, text: "fixture"),
                           DictationEntry(date: .now.addingTimeInterval(-2 * 86_400), text: "expired fixture")]
            try JSONEncoder().encode(entries).write(to: url)
            let dictation = Dictation(defaults: defaults, historyURL: url, vocabularyDirectory: url.deletingPathExtension())
            #expect(dictation.history.count == 2)
            dictation.historyRetention = .oneDay
            #expect(dictation.history == Array(entries.prefix(1)))
            dictation.historyRetention = .off
            #expect(dictation.history.isEmpty)
            #expect(Dictation(defaults: defaults, historyURL: url, vocabularyDirectory: url.deletingPathExtension()).history.isEmpty)
            #expect(MacSettings(defaults: defaults).historyRetention == .off)
        }
    }

    private func withFixture(_ body: (UserDefaults, URL) throws -> Void) throws {
        let domain = "ScribeM2Integration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let url = FileManager.default.temporaryDirectory.appending(path: domain + ".json")
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension())
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("notes"))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("last.json"))
        }
        try body(defaults, url)
    }
}
