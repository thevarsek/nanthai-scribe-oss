import Foundation

/// Identity and timestamps are independent of content so local edits can be reconciled later.
public struct Note: Identifiable, Codable, Hashable, Sendable {
    public enum Origin: String, Codable, Sendable { case dictation, pasted, typed }
    public var id: UUID
    public var createdAt: Date
    public var deletedAt: Date?
    public var modified: Date
    public var text: String
    /// The creation snapshot is independent of subsequent edits and copies.
    public private(set) var original: String?
    public var isEdited: Bool { text != (original ?? text) }
    public var origin: Origin
    public var sourceID: UUID?
    public var isKept: Bool
    /// Pins survive retention even for untouched dictations.
    public var pinned: Bool

    public var isRetained: Bool { isKept || pinned || origin != .dictation }
    public var date: Date { createdAt }
    public var title: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.isEmpty ? "New note" : String(first.prefix(80))
    }

    public init(id: UUID = UUID(), createdAt: Date = .now, modified: Date? = nil,
                text: String, origin: Origin, sourceID: UUID? = nil,
                isKept: Bool = false, pinned: Bool = false, original: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.modified = modified ?? createdAt
        self.text = text
        self.original = original ?? text
        self.origin = origin
        self.sourceID = sourceID
        self.isKept = isKept
        self.pinned = pinned
    }

    public init(id: UUID = UUID(), date: Date = .now, text: String, pinned: Bool = false) {
        self.init(id: id, createdAt: date, text: text, origin: .dictation, pinned: pinned)
    }

    public mutating func save(_ text: String, now: Date = .now) {
        self.text = text
        modified = now
        isKept = true
    }

    public func copy(text: String? = nil, now: Date = .now) -> Note {
        Note(createdAt: now, text: text ?? self.text, origin: origin, sourceID: id, isKept: true)
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, modified, deletedAt, text, origin, sourceID, isKept, date, pinned, original
    }

    /// Both legacy stores used `date`; older iOS entries may omit `pinned` entirely.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? values.decode(Date.self, forKey: .date)
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
        modified = try values.decodeIfPresent(Date.self, forKey: .modified) ?? createdAt
        text = try values.decode(String.self, forKey: .text)
        original = try values.decodeIfPresent(String.self, forKey: .original) ?? text
        origin = try values.decodeIfPresent(Origin.self, forKey: .origin) ?? .dictation
        sourceID = try values.decodeIfPresent(UUID.self, forKey: .sourceID)
        isKept = try values.decodeIfPresent(Bool.self, forKey: .isKept) ?? false
        pinned = try values.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(modified, forKey: .modified)
        try values.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try values.encode(text, forKey: .text)
        try values.encodeIfPresent(original, forKey: .original)
        try values.encode(origin, forKey: .origin)
        try values.encodeIfPresent(sourceID, forKey: .sourceID)
        try values.encode(isKept, forKey: .isKept)
        try values.encode(pinned, forKey: .pinned)
    }
}

public enum NoteRetention: String, CaseIterable, Identifiable, Sendable {
    case off, oneDay, thirtyDays, forever
    public var id: String { rawValue }
    public var title: String {
        switch self { case .off: "Off"; case .oneDay: "1 day"; case .thirtyDays: "30 days"; case .forever: "Forever" }
    }
    public func prune(_ notes: [Note], now: Date) -> [Note] {
        notes.filter { note in
            if note.isRetained { return true }
            switch self {
            case .off: return false
            case .forever: return true
            case .oneDay: return note.createdAt >= now.addingTimeInterval(-86_400)
            case .thirtyDays: return note.createdAt >= now.addingTimeInterval(-30 * 86_400)
            }
        }
    }
}

public struct NoteSection: Identifiable, Sendable {
    public let title: String
    public let notes: [Note]
    public var id: String { title }

    public static func sections(_ notes: [Note], search: String = "", now: Date = .now,
                                calendar: Calendar = .current) -> [NoteSection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let filtered = notes.filter { search.isEmpty || $0.text.localizedStandardContains(search) }
            .sorted { $0.createdAt > $1.createdAt }
        let unpinned = filtered.filter { !$0.pinned }
        return [("Pinned", filtered.filter(\.pinned)),
                ("Today", unpinned.filter { $0.createdAt >= today }),
                ("Yesterday", unpinned.filter { $0.createdAt >= yesterday && $0.createdAt < today }),
                ("Earlier", unpinned.filter { $0.createdAt < yesterday })]
            .filter { !$0.1.isEmpty }.map { NoteSection(title: $0.0, notes: $0.1) }
    }
}
