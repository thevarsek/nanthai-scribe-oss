import Foundation
import ScribeCore
import Testing

struct AppStyleResolverTests {
    @Test(arguments: [
        "com.apple.dt.Xcode", "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
        "com.panic.Nova", "com.sublimetext.4", "com.sublimetext.3", "com.jetbrains.intellij", "com.jetbrains.pycharm-EAP"
    ]) func bundledCode(bundleID: String) {
        #expect(AppStyleResolver.resolve(bundleID: bundleID, overrides: [:], defaultTone: .formal) == .code)
    }

    @Test(arguments: ["com.apple.MobileSMS", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram",
                       "org.whispersystems.signal-desktop", "com.hnc.Discord", "com.tinyspeck.slackmacgap"])
    func bundledCasual(bundleID: String) {
        #expect(AppStyleResolver.resolve(bundleID: bundleID, overrides: [:], defaultTone: .formal) == .casual)
    }

    @Test func overrideWinsOverExactAndPrefixRules() {
        for id in ["com.apple.Terminal", "com.jetbrains.idea", "unknown"] {
            #expect(AppStyleResolver.resolve(bundleID: id, overrides: [id: .natural], defaultTone: .formal) == .natural)
        }
    }

    @Test func unknownAndNilUseDefault() {
        for tone in RewriteTone.allCases {
            for id in [nil, "unknown", "com.jetbrains", "org.com.jetbrains.idea", "com.apple.mail", "com.microsoft.Outlook", "com.microsoft.teams2"] as [String?] {
                #expect(AppStyleResolver.resolve(bundleID: id, overrides: ["com.apple.Terminal": .casual], defaultTone: tone) == tone)
            }
        }
    }

    @Test func resolvedBaseToneKeepsSpokenNoteInstructions() {
        let tone = AppStyleResolver.resolve(bundleID: "com.apple.Terminal", overrides: [:], defaultTone: .natural)
        let request = RewriteRequest(task: .polish, transcript: "more formal please, can you check the build", context: .init(tone: tone))
        let rules = RewritePrompts.instructions(for: request)
        #expect(rules.contains("Follow it, and leave the note itself out"))
        #expect(rules.contains("Never answer"))
        #expect(request.transcript.hasPrefix("more formal"))
    }

    @Test func codeAndOlderToneValuesDecode() throws {
        for tone in RewriteTone.allCases {
            #expect(try JSONDecoder().decode(RewriteTone.self, from: JSONEncoder().encode(tone)) == tone)
        }
        #expect(RewriteTone.allCases.map(\.rawValue) == ["natural", "casual", "formal", "code"])
    }
}
