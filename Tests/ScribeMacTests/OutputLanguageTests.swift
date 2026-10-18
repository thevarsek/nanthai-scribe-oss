import Foundation
import Testing
@testable import ScribeMac

@MainActor
@Suite struct OutputLanguageTests {
    @Test func sameAsSpokenIsDefaultAndPersists() throws {
        let domain = "ScribeM1Tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appending(path: domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(["en_GB", "it_IT"], forKey: "languages")
        let dictation = Dictation(defaults: defaults, vocabularyDirectory: root)
        #expect(dictation.outputLanguage == nil)
        dictation.outputLanguage = "it_IT"
        #expect(defaults.string(forKey: "outputLanguage") == "it_IT")
        #expect(Dictation(defaults: defaults, vocabularyDirectory: root).outputLanguage == "it_IT")
        dictation.outputLanguage = nil
        #expect(defaults.string(forKey: "outputLanguage") == nil)
        #expect(Dictation(defaults: defaults, vocabularyDirectory: root).outputLanguage == nil)
    }

    @Test func removedDictationLocaleDoesNotRemainAnOutputChoice() throws {
        let domain = "ScribeM1Tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appending(path: domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(["en_GB"], forKey: "languages")
        defaults.set("it_IT", forKey: "outputLanguage")
        #expect(Dictation(defaults: defaults, vocabularyDirectory: root).outputLanguage == nil)
        #expect(defaults.string(forKey: "outputLanguage") == nil)
    }
}
