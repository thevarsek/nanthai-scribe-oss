import Foundation

public struct UnreadableItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public init(id: UUID) { self.id = id }
}

/// Each note is independently replaceable: one damaged file cannot hide the rest of Library.
public struct NoteStore: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    private var orderURL: URL { root.appending(path: "order.json") }
    public func file(_ id: UUID) -> URL { root.appending(path: id.uuidString + ".json") }
    public func migrate(_ data: Data) throws {
        guard let items = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: file(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), options: .atomic)
            return
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var order: [UUID] = []
        for (index, item) in items.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: item, options: [.fragmentsAllowed])
            let note = try? JSONDecoder().decode(Note.self, from: data)
            let object = item as? [String: Any]
            let fallback = UUID(uuidString: String(format: "00000000-0000-0000-0001-%012llx", UInt64(index + 1)))!
            let id = note?.id ?? (object?["id"] as? String).flatMap(UUID.init(uuidString:)) ?? fallback
            order.append(id)
            if !FileManager.default.fileExists(atPath: file(id).path) { try data.write(to: file(id), options: .atomic) }
        }
        try JSONEncoder().encode(order).write(to: orderURL, options: .atomic)
    }
    public func load() throws -> (notes: [Note], unreadable: [UnreadableItem]) {
        guard FileManager.default.fileExists(atPath: root.path) else { return ([], []) }
        var notes: [Note] = [], unreadable: [UnreadableItem] = []
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard file.pathExtension == "json", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            do {
                let note = try JSONDecoder().decode(Note.self, from: Data(contentsOf: file))
                guard note.id == id else { throw CocoaError(.fileReadCorruptFile) }
                notes.append(note)
            } catch { unreadable.append(.init(id: id)) }
        }
        let order = (try? Data(contentsOf: orderURL)).flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return (notes.sorted {
            let left = ranks[$0.id] ?? Int.max, right = ranks[$1.id] ?? Int.max
            return left == right ? $0.createdAt > $1.createdAt : left < right
        }, unreadable)
    }
    public func save(_ notes: [Note], removing ids: Set<UUID> = []) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for note in notes {
            let data = try JSONEncoder().encode(note)
            if (try? Data(contentsOf: file(note.id))) != data { try data.write(to: file(note.id), options: .atomic) }
        }
        let order = try JSONEncoder().encode(notes.map(\.id))
        if (try? Data(contentsOf: orderURL)) != order { try order.write(to: orderURL, options: .atomic) }
        for id in ids { try delete(id) }
    }
    public func purgeDeleted(now: Date = .now) throws {
        for note in try load().notes where RecentlyDeleted.isExpired(note.deletedAt, now: now) { try delete(note.id) }
    }
    public func delete(_ id: UUID) throws {
        if FileManager.default.fileExists(atPath: file(id).path) { try FileManager.default.removeItem(at: file(id)) }
    }
}
