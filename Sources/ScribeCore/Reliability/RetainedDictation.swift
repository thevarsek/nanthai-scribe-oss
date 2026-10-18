import AVFoundation
import Foundation

/// A failed take has its own durable audio, independent of transcript-history retention.
public struct RetainedDictation: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public private(set) var folder: URL
    public let languages: [String]
    public var file: URL { folder.appending(path: "audio.caf") }
    public static var root: URL { URL.applicationSupportDirectory.appending(path: "Scribe/Retry", directoryHint: .isDirectory) }
    public init(root: URL = Self.root, languages: [String]) throws {
        id = UUID(); folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        self.languages = languages
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appending(path: "take.json"), options: .atomic)
    }
    public static func load(root: URL = Self.root) -> [Self] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder -> Self? in
            guard var take = try? JSONDecoder().decode(Self.self, from: Data(contentsOf: folder.appending(path: "take.json"))) else { return nil }
            take.folder = folder
            return take
        }
            .filter { MeetingAudioFiles.hasAudio($0.file) }
    }
    public func remove() throws { try FileManager.default.removeItem(at: folder) }
    public func transcribe(parakeet: ParakeetTranscriber? = nil) async throws -> String {
        let locale = await MeetingLanguage.detect(files: [file], among: languages.map(Locale.init(identifier:)), parakeet: parakeet)
        return try await MeetingTranscriber.transcribe(file: file, locale: locale, speakerID: "you", parakeet: parakeet)
            .map(\.text).joined(separator: " ")
    }
}
