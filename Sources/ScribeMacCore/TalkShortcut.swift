import Foundation

/// Hardware key codes make pedals and function keys independent of the current layout.
public enum TalkShortcut: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let control = Self(rawValue: 1)
        public static let option = Self(rawValue: 2)
        public static let command = Self(rawValue: 4)
        public static let shift = Self(rawValue: 8)
        public static let primary: Self = [.control, .option, .command]

        public var titles: [String] {
            [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .compactMap { contains($0.0) ? $0.1 : nil }
        }
    }

    case modifier(TalkKey)
    case key(code: UInt16, modifiers: Modifiers, label: String)

    public static let rightOption: Self = .modifier(.rightOption)
    public static let rightCommand: Self = .modifier(.rightCommand)
    public static let rightControl: Self = .modifier(.rightControl)
    public static let fn: Self = .modifier(.fn)
    public static let controlOptionSpace: Self = .key(code: 49, modifiers: [.control, .option], label: "Space")
    public static let f13: Self = .key(code: 105, modifiers: [], label: "F13")
    public static let presets: [Self] = [.rightOption, .rightCommand, .fn, .controlOptionSpace, .f13]

    public static let functionKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                                                  103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    public var keyCaps: [String] {
        switch self {
        case .modifier(let key): [key.shortcutTitle]
        case .key(_, let modifiers, let label): modifiers.titles + [label]
        }
    }
    public var title: String { keyCaps.joined() }

    public enum Validation: Equatable, Sendable {
        case accepted, rejected, conflict
        public var message: String? {
            switch self {
            case .accepted: nil
            case .rejected: "Add ⌃, ⌥ or ⌘"
            case .conflict: "That shortcut is used by macOS."
            }
        }
    }

    public var validation: Validation {
        switch self {
        case .modifier: return .accepted
        case .key(let code, let modifiers, _):
            guard code < 128, ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code),
                  modifiers.rawValue & ~UInt8(15) == 0 else { return .rejected }
            guard !modifiers.intersection(.primary).isEmpty ||
                    (modifiers.isEmpty && Self.functionKeyCodes.contains(code)) else { return .rejected }
            // Common macOS launchers, app switching, input sources, screenshots and Mission Control.
            if (modifiers == .command && [48, 49].contains(code)) ||
                (modifiers == [.command, .shift] && [48, 20, 21, 23].contains(code)) ||
                (modifiers == .control && [49, 123, 124, 125, 126].contains(code)) ||
                (modifiers == [.control, .shift] && code == 49) ||
                (modifiers == [.command, .option] && [49, 53].contains(code)) ||
                (modifiers == [.command, .control] && code == 49) {
                return .conflict
            }
            return .accepted
        }
    }
}
