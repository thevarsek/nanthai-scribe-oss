import Foundation
import Testing
@testable import ScribeMacCore

@Suite struct MacSettingsTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "ScribeM2Tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func removedNoisePreferenceIsDeletedOnLaunch() throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: "reduceBackgroundNoise")
            _ = MacSettings(defaults: defaults)
            #expect(defaults.object(forKey: "reduceBackgroundNoise") == nil)
        }
    }

    @Test func defaultsMatchTheFirstLaunchDesign() throws {
        try withDefaults { defaults in
            let settings = MacSettings(defaults: defaults)
            #expect(settings.talkKey == .rightOption)
            #expect(settings.soundsEnabled)
            #expect(settings.engine == .apple)
            #expect(settings.useScreenContext)
            #expect(settings.historyRetention == .forever)
            #expect(!settings.onboardingDone)
        }
    }

    @Test func choicesPersistAcrossInstances() throws {
        try withDefaults { defaults in
            let settings = MacSettings(defaults: defaults)
            settings.talkKey = .fn
            settings.soundsEnabled = false
            settings.engine = .gemma
            settings.useScreenContext = false
            settings.historyRetention = .thirtyDays
            settings.onboardingDone = true
            let restored = MacSettings(defaults: defaults)
            #expect(restored.talkKey == .fn)
            #expect(!restored.soundsEnabled)
            #expect(restored.engine == .gemma)
            #expect(!restored.useScreenContext)
            #expect(restored.historyRetention == .thirtyDays)
            #expect(restored.onboardingDone)
            #expect(defaults.object(forKey: "useScreenContext") as? Bool == false)
        }
    }

    @Test func unknownEnumValuesUseDefaults() throws {
        try withDefaults { defaults in
            for key in ["talkKey", "engine", "historyRetention"] { defaults.set("unknown", forKey: key) }
            let settings = MacSettings(defaults: defaults)
            #expect(settings.talkKey == .rightOption)
            #expect(settings.engine == .apple)
            #expect(settings.historyRetention == .forever)
        }
    }

    @Test func existingSoundPreferenceIsPreservedUntilChanged() throws {
        try withDefaults { defaults in
            defaults.set(false, forKey: "playsSounds")
            let settings = MacSettings(defaults: defaults)
            #expect(!settings.soundsEnabled)
            settings.soundsEnabled = true
            #expect(settings.soundsEnabled)
            #expect(defaults.object(forKey: "soundsEnabled") as? Bool == true)
        }
    }

    @Test func everyEnumCaseRoundTrips() throws {
        try withDefaults { defaults in
            let settings = MacSettings(defaults: defaults)
            for value in TalkKey.allCases { settings.talkKey = value; #expect(settings.talkKey == value) }
            for value in RewriteEngine.allCases { settings.engine = value; #expect(settings.engine == value) }
            for value in HistoryRetention.allCases { settings.historyRetention = value; #expect(settings.historyRetention == value) }
        }
    }
}
