import Foundation

public enum TalkKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case rightOption, rightCommand, rightControl, fn

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rightOption: "Right ⌥ Option"
        case .rightCommand: "Right ⌘ Command"
        case .rightControl: "Right ⌃ Control"
        case .fn: "fn"
        }
    }
    public var shortcutTitle: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .rightCommand: "Right ⌘"
        case .rightControl: "Right ⌃"
        case .fn: "fn"
        }
    }
}

public enum RewriteEngine: String, CaseIterable, Identifiable, Sendable {
    case apple, gemma

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .apple: "Apple Intelligence (built-in)"
        case .gemma: "Gemma 4 (4.36 GB download)"
        }
    }
}

/// Typed defaults shared by the app and its test fixtures. Setters write through, so a
/// later launch and other milestones see the same values without a separate save step.
public struct MacSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: "reduceBackgroundNoise")
        if defaults.data(forKey: "talkShortcut") == nil {
            let legacy = TalkKey(rawValue: defaults.string(forKey: "talkKey") ?? "") ?? .rightOption
            talkShortcut = .modifier(legacy)
        }
    }

    public var talkShortcut: TalkShortcut {
        get {
            guard let data = defaults.data(forKey: "talkShortcut"),
                  let shortcut = try? JSONDecoder().decode(TalkShortcut.self, from: data),
                  shortcut.validation == .accepted else { return .rightOption }
            return shortcut
        }
        nonmutating set {
            guard newValue.validation == .accepted,
                  let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: "talkShortcut")
            defaults.removeObject(forKey: "talkKey")
        }
    }

    /// Compatibility for callers that still set the original modifier preference.
    public var talkKey: TalkKey {
        get { if case .modifier(let key) = talkShortcut { key } else { .rightOption } }
        nonmutating set { talkShortcut = .modifier(newValue) }
    }

    public var soundsEnabled: Bool {
        get {
            defaults.object(forKey: "soundsEnabled") as? Bool
                ?? defaults.object(forKey: "playsSounds") as? Bool ?? true
        }
        nonmutating set { defaults.set(newValue, forKey: "soundsEnabled") }
    }

    public var engine: RewriteEngine {
        get { RewriteEngine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .apple }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "engine") }
    }

    public var useScreenContext: Bool {
        get { defaults.object(forKey: "useScreenContext") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "useScreenContext") }
    }

    public var historyRetention: HistoryRetention {
        get { HistoryRetention(rawValue: defaults.string(forKey: "historyRetention") ?? "") ?? .forever }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "historyRetention") }
    }

    public var onboardingDone: Bool {
        get { defaults.bool(forKey: "onboardingDone") }
        nonmutating set { defaults.set(newValue, forKey: "onboardingDone") }
    }
}
