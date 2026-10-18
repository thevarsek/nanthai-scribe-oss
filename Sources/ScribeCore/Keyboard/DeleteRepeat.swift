import Foundation

/// The clock and proxy stay in the keyboard; the repeat schedule is deterministic.
public struct DeleteRepeat: Sendable {
    public enum Unit: Sendable, Equatable { case character, word }
    public private(set) var nextRepeat: TimeInterval = 0.5
    public private(set) var hasRepeated = false

    public init() {}

    public mutating func repeatIfDue(elapsed: TimeInterval) -> Unit? {
        guard elapsed + 0.000_001 >= nextRepeat else { return nil }
        let unit: Unit = elapsed >= 2 ? .word : .character
        nextRepeat = elapsed + (unit == .word ? 0.25 : 0.1)
        hasRepeated = true
        return unit
    }

    /// Trailing whitespace belongs to the word being removed, as on the system key.
    public static func wordLength(before cursor: String) -> Int {
        let tail = cursor.reversed().drop(while: \.isWhitespace)
        return cursor.count - tail.count + tail.prefix(while: { !$0.isWhitespace }).count
    }
}
