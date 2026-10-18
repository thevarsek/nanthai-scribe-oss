import CryptoKit
import Foundation
import Testing
@testable import ScribeCore

struct ModelStoreTests {
    @Test func immutableCatalog() {
        for model in ModelCatalog.all {
            #expect(model.revision.count == 40)
            #expect(model.expectedTotalSize > 0)
            #expect(!model.files.isEmpty)
            #expect(model.files.allSatisfy { !$0.path.contains("..") && !$0.path.hasPrefix("/") })
            #expect(model.files.allSatisfy { $0.sha256?.count == 64 })
            #expect(model.downloadURL(for: model.files[0]).path.contains(model.revision))
        }
    }

    @Test func integrityRejectsWrongBytesAndWrongSize() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "weights")
        let data = Data("weights".utf8)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = ModelDescriptor.File(path: "weights", size: Int64(data.count), sha256: sha)
        try data.write(to: url)
        try await ModelStore.verify(file, at: url)
        try Data("WEIGHTS".utf8).write(to: url)
        await #expect(throws: ModelStoreError.self) { try await ModelStore.verify(file, at: url) }
        try Data("short".utf8).write(to: url)
        await #expect(throws: ModelStoreError.self) { try await ModelStore.verify(file, at: url) }
    }

    @Test @MainActor func presenceRequiresReceiptAndEveryFileAndDeleteIsOffline() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ModelStore(root: root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let fixture = ModelDescriptor(id: "fixture", displayName: "Fixture", repository: "none/none", revision: "pinned", credit: "test",
                                      files: [.init(path: "weights", size: 4, sha256: nil)])
        let directory = store.directory(for: fixture)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("test".utf8).write(to: directory.appending(path: "weights"))
        #expect(!store.isInstalled(fixture))
        try "pinned".write(to: directory.appending(path: ".installed"), atomically: true, encoding: .utf8)
        #expect(store.isInstalled(fixture))
        try Data().write(to: directory.appending(path: "weights"))
        #expect(!store.isInstalled(fixture))
        try await store.delete(fixture)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
