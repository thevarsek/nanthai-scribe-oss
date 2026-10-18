/// Picks a base tone only; spoken style instructions remain part of the rewrite prompt.
public enum AppStyleResolver: Sendable {
    public static let bundledRules: [String: RewriteTone] = [
        "com.apple.dt.Xcode": .code,
        "com.apple.Terminal": .code,
        "com.googlecode.iterm2": .code,
        "com.mitchellh.ghostty": .code,
        "dev.warp.Warp-Stable": .code,
        "com.microsoft.VSCode": .code,
        "com.todesktop.230313mzl4w4u92": .code,
        "dev.zed.Zed": .code,
        "com.panic.Nova": .code,
        "com.sublimetext.4": .code,
        "com.sublimetext.3": .code,
        "com.apple.MobileSMS": .casual,
        "net.whatsapp.WhatsApp": .casual,
        "ru.keepcoder.Telegram": .casual,
        "org.whispersystems.signal-desktop": .casual,
        "com.hnc.Discord": .casual,
        "com.tinyspeck.slackmacgap": .casual,
    ]

    public static func bundledTone(for bundleID: String) -> RewriteTone? {
        if bundleID.hasPrefix("com.jetbrains.") { return .code }
        return bundledRules[bundleID]
    }

    public static func resolve(bundleID: String?, overrides: [String: RewriteTone],
                               defaultTone: RewriteTone) -> RewriteTone {
        guard let bundleID else { return defaultTone }
        return overrides[bundleID] ?? bundledTone(for: bundleID) ?? defaultTone
    }
}
