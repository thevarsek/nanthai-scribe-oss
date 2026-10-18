import Foundation

public struct RecordingImport: Sendable, Equatable {
    public static let extensions = ["m4a", "mp3", "wav", "aac", "caf", "aiff"]
    public let title: String
    public let createdAt: Date
    public let fileExtension: String

    public init(url: URL, fallbackDate: Date = .now) throws {
        let ext = url.pathExtension.lowercased()
        guard Self.extensions.contains(ext) else { throw CocoaError(.fileReadUnsupportedScheme) }
        title = url.deletingPathExtension().lastPathComponent
        createdAt = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? fallbackDate
        fileExtension = ext
    }

    /// Copy first, then publish the manifest. The caller's original is never processed or removed.
    public func copy(from source: URL, into store: MeetingStore, languages: [String], keepAudio: Bool = false) async throws -> Meeting {
        var meeting = Meeting(title: title, startedAt: createdAt, state: .processing, languages: languages, retainsAudio: keepAudio)
        let folder = store.directory(meeting.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "imported." + fileExtension
        do {
            try FileManager.default.copyItem(at: source.resolvingSymlinksInPath(), to: folder.appending(path: name))
            meeting.audio = [.init(stream: MeetingAudioSegment.system, file: name, offset: 0)]
            meeting.duration = MeetingAudioFiles.duration(of: folder.appending(path: name)) ?? 0
            meeting.endedAt = createdAt.addingTimeInterval(meeting.duration)
            try await store.save(meeting)
            return meeting
        } catch {
            try? await store.delete(meeting.id)
            throw error
        }
    }
}
