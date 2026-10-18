import Foundation

/// Immutable Hugging Face snapshots: checking availability never needs the network.
public struct ModelDescriptor: Codable, Sendable, Identifiable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public let path: String
        public let size: Int64
        public let sha256: String?
    }

    public let id: String
    public let displayName: String
    public let repository: String
    public let revision: String
    public let credit: String
    public let files: [File]
    public var expectedTotalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    public func downloadURL(for file: File) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.path)")!
    }
}

public enum ModelCatalog {
    public static let gemma = bundled("gemma-4-e2b")
    /// UI download copy must derive its size from this pinned snapshot.
    public static let gemmaDownloadBytes: Int64 = gemma.expectedTotalSize
    public static let parakeet = bundled("parakeet-v3")
    public static let meetingDiarizer = bundled("meeting-diarizer")
    public static let all = [gemma, parakeet, meetingDiarizer]

    private static func bundled(_ name: String) -> ModelDescriptor {
        // Native SwiftPM CLI accessors search the executable bundle root. A signed macOS
        // app must instead keep nested resource bundles inside Contents/Resources.
        let packaged = Bundle.main.url(forResource: "NanthAiScribe_ScribeCore", withExtension: "bundle")
            .flatMap { Bundle(url: $0) }
        let resources = packaged ?? Bundle.module
        // These manifests are versioned app resources, not mutable server responses.
        guard let url = resources.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let model = try? JSONDecoder().decode(ModelDescriptor.self, from: data) else {
            preconditionFailure("Missing model catalog resource: \(name)")
        }
        return model
    }
}
