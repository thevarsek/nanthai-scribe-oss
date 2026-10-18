import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import ScribeCore

/// Serves `weights` from huggingface.co and 403 from the expired CDN host, like Hugging Face
/// does once a signed redirect stored in resume data has expired. Never touches the network.
private final class StubHub: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    static let canonicalStatus = Mutex(200)
    static let body = Data("weights".utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let status = request.url?.host == "huggingface.co" ? Self.canonicalStatus.withLock { $0 } : 403
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: status == 200 ? Self.body : Data("Forbidden".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) @MainActor
struct ModelDownloadTests {
    let fixture = ModelDescriptor(id: "fixture", displayName: "Fixture", repository: "test/fixture", revision: "pinned",
                                  credit: "test", files: [.init(path: "weights", size: Int64(StubHub.body.count),
                                                                sha256: SHA256.hash(data: StubHub.body).map { String(format: "%02x", $0) }.joined())])

    private func makeStore() -> (ModelStore, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHub.self]
        StubHub.requests.withLock { $0 = [] }
        StubHub.canonicalStatus.withLock { $0 = 200 }
        return (ModelStore(root: root, sessionConfiguration: configuration), root)
    }

    /// Resume data in URLSession's format whose current request is an expired signed CDN URL.
    private func writeStaleResumeData(to url: URL) throws -> URL {
        let partial = FileManager.default.temporaryDirectory.appending(path: "CFNetworkDownload_\(UUID().uuidString).tmp")
        try Data("wei".utf8).write(to: partial)
        var request = URLRequest(url: URL(string: "https://cdn.test/xet-bridge/weights?Expires=1700000000")!)
        request.setValue("bytes=3-", forHTTPHeaderField: "Range")
        let archived = try NSKeyedArchiver.archivedData(withRootObject: request as NSURLRequest, requiringSecureCoding: false)
        let info: [String: Any] = [
            "NSURLSessionResumeInfoVersion": 2, "NSURLSessionDownloadURL": request.url!.absoluteString,
            "NSURLSessionResumeBytesReceived": 3, "NSURLSessionResumeInfoTempFileName": partial.lastPathComponent,
            "NSURLSessionResumeCurrentRequest": archived, "NSURLSessionResumeOriginalRequest": archived,
            "NSURLSessionResumeEntityTag": "\"stale\"",
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: url)
        return partial
    }

    @Test func rejectedResumeDiscardsStateAndRetriesFromCanonicalURL() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = store.directory(for: fixture).appending(path: "weights")
        let partial = try writeStaleResumeData(to: destination.appendingPathExtension("resume"))
        defer { try? FileManager.default.removeItem(at: partial) }

        try await store.download(fixture)

        let requests = StubHub.requests.withLock { $0 }
        #expect(requests.map(\.url?.host) == ["cdn.test", "huggingface.co"])
        #expect(requests.last?.url == fixture.downloadURL(for: fixture.files[0]))
        #expect(requests.last?.value(forHTTPHeaderField: "Range") == nil)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathExtension("resume").path))
        #expect(store.isInstalled(fixture))
        #expect(store.progress[fixture.id]?.status == .installed)
    }

    @Test func persistentRejectionRetriesOnceAndShowsReadableError() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        StubHub.canonicalStatus.withLock { $0 = 403 }

        await #expect(throws: ModelStoreError.self) { try await store.download(fixture) }

        #expect(StubHub.requests.withLock { $0.count } == 2)
        #expect(store.progress[fixture.id]?.status == .failed("Download failed. Check your connection and try again."))
        #expect(!store.isInstalled(fixture))
    }

    @Test func installedStateComesFromFilesOnDisk() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = store.directory(for: fixture)
        let weights = directory.appending(path: "weights")
        #expect(store.diskProgress(fixture).status == .absent)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("wei".utf8).write(to: weights)
        #expect(store.diskProgress(fixture).status == .paused)

        // Complete, verified files without a receipt are adopted locally, with no request.
        try StubHub.body.write(to: weights)
        #expect(store.diskProgress(fixture).status == .verifying)
        for _ in 0..<200 where store.progress[fixture.id]?.status != .installed { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.progress[fixture.id]?.status == .installed)
        #expect(store.isInstalled(fixture))
        #expect(StubHub.requests.withLock { $0.isEmpty })

        // Right size, wrong bytes: never installed; the corrupt file is removed.
        try FileManager.default.removeItem(at: directory.appending(path: ".installed"))
        try Data("WEIGHTS".utf8).write(to: weights)
        _ = store.diskProgress(fixture)
        for _ in 0..<200 where FileManager.default.fileExists(atPath: weights.path) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.progress[fixture.id]?.status == .absent)
        #expect(!store.isInstalled(fixture))
    }
}
