import Foundation
import UniformTypeIdentifiers

public extension UTType {
    static let scribeBackup = UTType(exportedAs: "tech.nanthai.scribe.backup", conformingTo: .package)
}

public enum BackupMerge {
    /// Ties keep the local item, making a repeated import a no-op.
    public static func items<Item: Identifiable>(_ local: [Item], _ incoming: [Item],
                                                modified: (Item) -> Date) -> [Item] where Item.ID: Hashable {
        var result = local
        var indices = Dictionary(local.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for item in incoming {
            if let index = indices[item.id] {
                if modified(item) > modified(result[index]) { result[index] = item }
            } else { indices[item.id] = result.count; result.append(item) }
        }
        return result
    }
}

/// This manifest intentionally has no device preferences or Recently Deleted contents.
public struct LibraryBackup: Codable, Sendable, Equatable {
    public var version = 1
    public var notes: [Note]
    public var meetings: [Meeting]
    public var dictionary: [DictionaryEntry]
    public var snippets: [Snippet]
    public var learning: LearningStore.Document

    public init(notes: [Note], meetings: [Meeting], dictionary: [DictionaryEntry], snippets: [Snippet],
                learning: LearningStore.Document) {
        self.notes = notes.filter { $0.deletedAt == nil }
        self.meetings = meetings.filter { $0.deletedAt == nil }
        self.dictionary = dictionary; self.snippets = snippets; self.learning = learning
    }
    public func merging(_ incoming: Self) -> Self {
        var learned = learning
        learned.merge(incoming.learning)
        return Self(notes: BackupMerge.items(notes, incoming.notes, modified: { $0.modified }),
                    meetings: BackupMerge.items(meetings, incoming.meetings, modified: { $0.modified }),
                    dictionary: BackupMerge.items(dictionary, incoming.dictionary, modified: { $0.modified }),
                    snippets: BackupMerge.items(snippets, incoming.snippets, modified: { $0.modified }), learning: learned)
    }

    public func fileWrapper(meetingRoot: URL) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var files: [String: FileWrapper] = [:]
        func json<T: Encodable>(_ value: T, _ name: String) throws { files[name] = FileWrapper(regularFileWithContents: try encoder.encode(value)) }
        try json(version, "version.json"); try json(notes, "notes.json"); try json(meetings, "meetings.json")
        try json(dictionary, "dictionary.json"); try json(snippets, "snippets.json"); try json(learning, "corrections.json")
        var audio: [String: FileWrapper] = [:]
        for meeting in meetings {
            var segments: [String: FileWrapper] = [:]
            for segment in meeting.audio {
                try Self.validateFileName(segment.file)
                let url = meetingRoot.appending(path: meeting.id.uuidString).appending(path: segment.file)
                if FileManager.default.fileExists(atPath: url.path) { segments[segment.file] = try FileWrapper(url: url, options: .immediate) }
            }
            if !segments.isEmpty { audio[meeting.id.uuidString] = FileWrapper(directoryWithFileWrappers: segments) }
        }
        files["audio"] = FileWrapper(directoryWithFileWrappers: audio)
        return FileWrapper(directoryWithFileWrappers: files)
    }

    public init(fileWrapper: FileWrapper) throws {
        func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
            guard let data = fileWrapper.fileWrappers?[name]?.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            return try JSONDecoder().decode(type, from: data)
        }
        version = try decode(Int.self, "version.json")
        guard version == 1 else { throw CocoaError(.fileReadUnknown) }
        notes = try decode([Note].self, "notes.json")
        meetings = try decode([Meeting].self, "meetings.json")
        dictionary = try decode([DictionaryEntry].self, "dictionary.json")
        snippets = try decode([Snippet].self, "snippets.json")
        learning = try decode(LearningStore.Document.self, "corrections.json")
        notes.removeAll { $0.deletedAt != nil }; meetings.removeAll { $0.deletedAt != nil }
        for meeting in meetings { for segment in meeting.audio { try Self.validateFileName(segment.file) } }
    }

    /// Install audio only for incoming winners, preserving local edits and existing recordings.
    public func restoreAudio(from wrapper: FileWrapper, local: [Meeting], meetingRoot: URL) throws {
        for meeting in meetings {
            if let current = local.first(where: { $0.id == meeting.id }), current.modified >= meeting.modified { continue }
            for segment in meeting.audio {
                try Self.validateFileName(segment.file)
                guard let file = wrapper.fileWrappers?["audio"]?.fileWrappers?[meeting.id.uuidString]?.fileWrappers?[segment.file],
                      let data = file.regularFileContents else { continue }
                let directory = meetingRoot.appending(path: meeting.id.uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appending(path: segment.file), options: .atomic)
            }
        }
    }
    private static func validateFileName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { throw CocoaError(.fileReadCorruptFile) }
    }
}
