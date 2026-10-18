import Foundation

/// Anchors describe only one insertion. A changed boundary makes later edits ambiguous.
public struct CorrectionSpan: Equatable, Sendable {
    public let inserted: String
    public let prefix: String
    public let suffix: String
    public let startedAt: Date

    public init(inserted: String, prefix: String, suffix: String, at now: Date = .now) {
        self.inserted = inserted; self.prefix = prefix; self.suffix = suffix; startedAt = now
    }
    public func current(in text: String, at now: Date) -> String? {
        guard now.timeIntervalSince(startedAt) >= 0, now.timeIntervalSince(startedAt) <= 60,
              text.hasPrefix(prefix), text.hasSuffix(suffix), text.count >= prefix.count + suffix.count else { return nil }
        return String(text.dropFirst(prefix.count).dropLast(suffix.count))
    }
}
