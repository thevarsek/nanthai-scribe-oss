import Foundation
import Testing
@testable import ScribeMac

@MainActor
@Suite struct ScreenContextSettingTests {
    @Test func enabledByDefaultAndPersistsOnTheSharedKey() throws {
        let domain = "ScribeM3Tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appending(path: domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let dictation = Dictation(defaults: defaults, vocabularyDirectory: root)
        #expect(dictation.useScreenContext)
        dictation.useScreenContext = false
        #expect(defaults.bool(forKey: "useScreenContext") == false)
        #expect(Dictation(defaults: defaults, vocabularyDirectory: root).useScreenContext == false)
        dictation.useScreenContext = true
        #expect(Dictation(defaults: defaults, vocabularyDirectory: root).useScreenContext)
    }
}
