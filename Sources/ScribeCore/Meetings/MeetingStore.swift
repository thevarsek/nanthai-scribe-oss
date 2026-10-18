import Foundation

/// Atomic JSON snapshots; audio is owned by the recording session and is never copied here implicitly.
public actor MeetingStore {
    public nonisolated let root: URL
    public private(set) var unreadable: [UnreadableItem] = []
    public init(root: URL) { self.root = root }
    public nonisolated func directory(_ id: UUID) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }
    public func save(_ meeting: Meeting) throws {
        let folder = directory(meeting.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meeting).write(to: folder.appending(path: "meeting.json"), options: .atomic)
    }
    public func load() throws -> [Meeting] {
        unreadable = []
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var meetings: [Meeting] = []
        for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            do {
                let meeting = try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: folder.appending(path: "meeting.json")))
                guard meeting.id == id else { throw CocoaError(.fileReadCorruptFile) }
                meetings.append(meeting)
            } catch { unreadable.append(.init(id: id)) }
        }
        return meetings.sorted { $0.startedAt > $1.startedAt }
    }

    public func purgeDeleted(now: Date = .now) throws {
        for meeting in try load() where RecentlyDeleted.isExpired(meeting.deletedAt, now: now) { try delete(meeting.id) }
    }
    public func delete(_ id: UUID) throws {
        let folder = directory(id)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}

public struct MeetingDay: Identifiable, Sendable {
    public var date: Date
    public var title: String
    public var meetings: [Meeting]
    public var id: Date { date }
}
public enum MeetingGrouping {
    public static func days(_ meetings: [Meeting], now: Date = .now, calendar: Calendar = .current) -> [MeetingDay] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        return Dictionary(grouping: meetings) { calendar.startOfDay(for: $0.startedAt) }
            .sorted { $0.key > $1.key }.map { date, values in
                let title = date == today ? "Today" : date == yesterday ? "Yesterday" : date.formatted(date: .abbreviated, time: .omitted)
                return MeetingDay(date: date, title: title, meetings: values.sorted { $0.startedAt > $1.startedAt })
            }
    }
}
