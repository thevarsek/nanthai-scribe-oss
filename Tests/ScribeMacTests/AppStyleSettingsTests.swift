import Foundation
import ScribeCore
import Testing
@testable import ScribeMac

@MainActor
struct AppStyleSettingsTests {
    @Test func persistenceDefaultTrackingAndReset() throws {
        let suite = "M10Styles-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppStyleSettings(defaults: defaults)
        #expect(settings.choice(for: "com.apple.Terminal") == "code")
        settings.set("default", for: "com.apple.Terminal")
        settings.set("code", for: "example.editor")
        let restored = AppStyleSettings(defaults: defaults)
        #expect(restored.overrides(defaultTone: .natural)["com.apple.Terminal"] == .natural)
        #expect(restored.overrides(defaultTone: .formal)["com.apple.Terminal"] == .formal)
        #expect(restored.overrides(defaultTone: .natural)["example.editor"] == .code)
        let json = try JSONDecoder().decode([String: String].self, from: #require(defaults.data(forKey: "appStyleOverrides")))
        #expect(json == ["com.apple.Terminal": "default", "example.editor": "code"])
        restored.reset("com.apple.Terminal")
        restored.reset("example.editor")
        #expect(restored.choice(for: "com.apple.Terminal") == "code")
        #expect(AppStyleSettings(defaults: defaults).choices.isEmpty)
    }

    @Test func damagedPreferencesFallBackToBundledRules() throws {
        let suite = "M10Styles-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "appStyleOverrides")
        let settings = AppStyleSettings(defaults: defaults)
        #expect(settings.choices.isEmpty)
        #expect(AppStyleResolver.resolve(bundleID: "com.apple.Terminal", overrides: settings.overrides(defaultTone: .formal), defaultTone: .formal) == .code)
        defaults.set(try JSONEncoder().encode(["unknown": "future-tone"]), forKey: "appStyleOverrides")
        #expect(AppStyleSettings(defaults: defaults).overrides(defaultTone: .natural).isEmpty)
    }
}
