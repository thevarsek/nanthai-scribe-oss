import Foundation

/// Prompt history travels with the observations, so app and keyboard share one cooldown.
public struct CorrectionLog: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case suggested = "Suggested", ignored = "Ignored" }
    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public var id: String { pair.key }
        public var pair: CorrectionPair
        public var timesSeen: Int
        public var modified: Date?
        public var lastSeen: Date
        public var state: State = .suggested
        public var deferrals = 0
        public var askAfter = 1
        public var caption: String { "Seen \(timesSeen)× · \(state.rawValue)" }
    }
    public private(set) var entries: [Entry] = []
    public private(set) var lastPrompt: Date?
    public init() {}
    public var newestFirst: [Entry] { entries.sorted { $0.lastSeen > $1.lastSeen } }

    /// Call once per observed correction, never on every polling tick or editor redraw.
    @discardableResult
    public mutating func record(_ pair: CorrectionPair, at now: Date, canAsk: Bool) -> Bool {
        let index: Int
        if let existing = entries.firstIndex(where: { $0.id == pair.key }) {
            index = existing; entries[index].pair = pair; entries[index].timesSeen += 1; entries[index].lastSeen = now; entries[index].modified = now
        } else {
            index = entries.count
            entries.append(Entry(pair: pair, timesSeen: 1, lastSeen: now))
        }
        guard canAsk, entries[index].state != .ignored, entries[index].timesSeen >= entries[index].askAfter,
              lastPrompt.map({ now.timeIntervalSince($0) >= 600 }) ?? true else { return false }
        lastPrompt = now
        return true
    }

    public mutating func notNow(_ pair: CorrectionPair) {
        guard let index = entries.firstIndex(where: { $0.id == pair.key }) else { return }
        entries[index].modified = .now
        entries[index].deferrals += 1
        entries[index].askAfter = entries[index].timesSeen + 3
        if entries[index].deferrals >= 2 { entries[index].state = .ignored }
    }
    public mutating func ignore(_ pair: CorrectionPair) {
        guard let index = entries.firstIndex(where: { $0.id == pair.key }) else { return }
        entries[index].modified = .now
        entries[index].state = .ignored
    }
    public mutating func merge(_ other: Self) {
        entries = BackupMerge.items(entries, other.entries, modified: { $0.modified ?? $0.lastSeen })
        lastPrompt = [lastPrompt, other.lastPrompt].compactMap { $0 }.max()
    }
    public mutating func forget(_ pair: CorrectionPair) { entries.removeAll { $0.id == pair.key } }
}
