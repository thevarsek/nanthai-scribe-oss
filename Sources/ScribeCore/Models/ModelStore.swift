import CryptoKit
import Foundation
import Observation
import os

public enum ModelStoreError: LocalizedError, Sendable {
    case insufficientSpace(required: Int64, available: Int64)
    case verificationFailed(String)
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .insufficientSpace(let required, let available):
            "Not enough space. The model needs \(Self.bytes(required)); \(Self.bytes(available)) is available."
        case .verificationFailed, .httpStatus: Self.downloadFailed
        }
    }

    /// Shown for any transfer or integrity failure: status codes and file names mean nothing to people.
    public static let downloadFailed = "Download failed. Check your connection and try again."

    /// Hugging Face's signed CDN redirects expire (about an hour). Resume data keeps the
    /// redirected URL, so a later resume gets 403; 416 means the partial bytes no longer fit.
    var rejectsStaleTransfer: Bool {
        if case .httpStatus(let status) = self { [401, 403, 416].contains(status) } else { false }
    }

    private static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}

/// The only optional-model downloader. Constructing, inspecting, and deleting are offline.
/// Call `download` only in response to a user's download/resume action.
@Observable @MainActor
public final class ModelStore {
    public enum Status: Sendable, Equatable {
        case absent, downloading, verifying, paused, installed
        case failed(String)
    }

    public struct Progress: Sendable, Equatable {
        public var status: Status = .absent
        public var completedBytes: Int64 = 0
        public var totalBytes: Int64 = 0
        public var fraction: Double { totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0 }

        public init(status: Status = .absent, completedBytes: Int64 = 0, totalBytes: Int64 = 0) {
            self.status = status
            self.completedBytes = completedBytes
            self.totalBytes = totalBytes
        }
    }

    public let root: URL
    public private(set) var progress: [String: Progress] = [:]
    @ObservationIgnored private var downloads: [String: Task<Void, Error>] = [:]
    @ObservationIgnored private var transferIDs: [String: UUID] = [:]
    @ObservationIgnored private var transfers: [String: ModelTransfer] = [:]
    @ObservationIgnored private let sessionConfiguration: URLSessionConfiguration
    private static let logger = Logger(subsystem: "tech.nanthai.Scribe", category: "ModelStore")

    /// On iOS pass a Models subdirectory of the app's shared app-group container.
    /// Tests inject a configuration with a stub `URLProtocol`; the app keeps the ephemeral default.
    public init(root: URL, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.root = root
        self.sessionConfiguration = sessionConfiguration
        for model in ModelCatalog.all { progress[model.id] = diskProgress(model) }
    }

    /// Status comes from the files on disk, never from remembered state, so a finished
    /// download is never offered again and a partial one offers Resume instead of Download.
    func diskProgress(_ model: ModelDescriptor) -> Progress {
        let directory = directory(for: model)
        if Self.isInstalled(model, at: directory) {
            return Progress(status: .installed, completedBytes: model.expectedTotalSize, totalBytes: model.expectedTotalSize)
        }
        let sized = model.files.filter { Self.size(of: directory.appending(path: $0.path)) == $0.size }
        if sized.count == model.files.count {
            // Every file is present but the receipt is missing (e.g. killed before writing it):
            // hash locally and adopt, with no network.
            Task { await self.adoptVerifiedFiles(model) }
            return Progress(status: .verifying, completedBytes: model.expectedTotalSize, totalBytes: model.expectedTotalSize)
        }
        let partial = model.files.contains { file in
            let url = directory.appending(path: file.path)
            return Self.size(of: url) != nil || FileManager.default.fileExists(atPath: url.appendingPathExtension("resume").path)
        }
        return Progress(status: partial ? .paused : .absent, completedBytes: sized.reduce(0) { $0 + $1.size },
                        totalBytes: model.expectedTotalSize)
    }

    private func adoptVerifiedFiles(_ model: ModelDescriptor) async {
        let directory = directory(for: model)
        var verified = true
        for file in model.files where (try? await Self.verify(file, at: directory.appending(path: file.path))) == nil {
            try? FileManager.default.removeItem(at: directory.appending(path: file.path))
            verified = false
        }
        guard downloads[model.id] == nil else { return }
        if verified, (try? model.revision.write(to: directory.appending(path: ".installed"), atomically: true, encoding: .utf8)) != nil {
            progress[model.id] = Progress(status: .installed, completedBytes: model.expectedTotalSize, totalBytes: model.expectedTotalSize)
        } else {
            progress[model.id] = diskProgress(model)
        }
    }

    private nonisolated static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
    }

    #if os(macOS)
    public convenience init() {
        self.init(root: Self.defaultRoot)
    }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "NanthAi Scribe/Models", directoryHint: .isDirectory)
    }
    #endif

    public func directory(for model: ModelDescriptor) -> URL { root.appending(path: model.id, directoryHint: .isDirectory) }
    public func isInstalled(_ model: ModelDescriptor) -> Bool { Self.isInstalled(model, at: directory(for: model)) }

    /// A receipt is written only after every downloaded file passed verification.
    /// Check lengths too, so incomplete/deleted files never count as installed.
    public nonisolated static func isInstalled(_ model: ModelDescriptor, at directory: URL) -> Bool {
        guard let revision = try? String(contentsOf: directory.appending(path: ".installed"), encoding: .utf8),
              revision == model.revision else { return false }
        return model.files.allSatisfy { size(of: directory.appending(path: $0.path)) == $0.size }
    }

    public func download(_ model: ModelDescriptor) async throws {
        if let existing = downloads[model.id] { return try await existing.value }
        let work = Task { try await self.performDownload(model) }
        downloads[model.id] = work
        defer { downloads[model.id] = nil; transfers[model.id] = nil; transferIDs[model.id] = nil }
        try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
            Task { @MainActor in self.transfers[model.id]?.cancel() }
        }
    }

    /// Waits for URLSession to persist resume data before returning.
    public func pause(_ model: ModelDescriptor) async {
        downloads[model.id]?.cancel()
        transfers[model.id]?.cancel()
        _ = try? await downloads[model.id]?.value
    }

    public func delete(_ model: ModelDescriptor) async throws {
        await pause(model)
        let url = directory(for: model)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        progress[model.id] = Progress(totalBytes: model.expectedTotalSize)
    }

    private func performDownload(_ model: ModelDescriptor) async throws {
        let directory = directory(for: model)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var excluded = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            var completed: Int64 = 0
            // Re-verify partial downloads on resume, including files completed in a previous run.
            var pending: [ModelDescriptor.File] = []
            for file in model.files {
                try Task.checkCancellation()
                let url = directory.appending(path: file.path)
                if (try? await Self.verify(file, at: url)) != nil { completed += file.size }
                else { pending.append(file) }
            }
            let required = pending.reduce(Int64(0)) { $0 + $1.size }
            let available = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
                ?? (FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? Int64 ?? 0)
            guard available >= required else {
                throw ModelStoreError.insufficientSpace(required: required, available: available)
            }
            progress[model.id] = Progress(status: .downloading, completedBytes: completed, totalBytes: model.expectedTotalSize)
            for file in pending {
                try Task.checkCancellation()
                let destination = directory.appending(path: file.path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    try await transfer(file, of: model, to: destination, baseline: completed)
                } catch let error as ModelStoreError where error.rejectsStaleTransfer {
                    // Retry once from the canonical huggingface.co URL, which issues a fresh signed redirect.
                    try? FileManager.default.removeItem(at: destination.appendingPathExtension("resume"))
                    try? FileManager.default.removeItem(at: destination)
                    try await transfer(file, of: model, to: destination, baseline: completed)
                }
                progress[model.id]?.status = .verifying
                do { try await Self.verify(file, at: destination) }
                catch { try? FileManager.default.removeItem(at: destination); throw error }
                completed += file.size
                progress[model.id]?.completedBytes = completed
            }
            try Task.checkCancellation()
            try model.revision.write(to: directory.appending(path: ".installed"), atomically: true, encoding: .utf8)
            progress[model.id] = Progress(status: .installed, completedBytes: completed, totalBytes: model.expectedTotalSize)
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError
            if !cancelled { Self.logFailure(error) }
            let message = (error as? ModelStoreError)?.errorDescription ?? ModelStoreError.downloadFailed
            progress[model.id, default: Progress(totalBytes: model.expectedTotalSize)].status =
                cancelled ? .paused : .failed(message)
            throw error
        }
    }

    private func transfer(_ file: ModelDescriptor.File, of model: ModelDescriptor, to destination: URL,
                          baseline: Int64) async throws {
        let transferID = UUID()
        transferIDs[model.id] = transferID
        progress[model.id]?.status = .downloading
        let transfer = ModelTransfer(destination: destination, configuration: sessionConfiguration) { [weak self] bytes in
            guard let self, self.transferIDs[model.id] == transferID,
                  self.progress[model.id]?.status == .downloading else { return }
            self.progress[model.id] = Progress(status: .downloading, completedBytes: baseline + bytes,
                                               totalBytes: model.expectedTotalSize)
        }
        transfers[model.id] = transfer
        try await transfer.download(model.downloadURL(for: file))
    }

    /// Status codes help diagnose CDN problems; URLs carry signatures, so they are never logged.
    private static func logFailure(_ error: Error) {
        #if DEBUG
        switch error {
        case ModelStoreError.httpStatus(let status): logger.debug("Model download HTTP \(status, privacy: .public)")
        case let error as URLError: logger.debug("Model download URLError \(error.code.rawValue, privacy: .public)")
        default: logger.debug("Model download failed: \(String(describing: type(of: error)), privacy: .public)")
        }
        #endif
    }

    /// Hash in bounded chunks off the UI actor; never map multi-gigabyte weights into RAM.
    nonisolated static func verify(_ file: ModelDescriptor.File, at url: URL) async throws {
        let worker = Task.detached(priority: .utility) {
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(file.size) else {
                throw ModelStoreError.verificationFailed(file.path)
            }
            guard let expected = file.sha256 else { return }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                hash.update(data: data)
            }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else {
                throw ModelStoreError.verificationFailed(file.path)
            }
        }
        try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}

/// One transfer at a time per model, with URLSession's opaque resume data kept beside it.
@MainActor
private final class ModelTransfer: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let configuration: URLSessionConfiguration
    private let onProgress: @MainActor (Int64) -> Void
    private var resumed = false
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancelling = false
    private var resumeURL: URL { destination.appendingPathExtension("resume") }

    init(destination: URL, configuration: URLSessionConfiguration, onProgress: @escaping @MainActor (Int64) -> Void) {
        self.destination = destination
        self.configuration = configuration
        self.onProgress = onProgress
    }

    func download(_ url: URL) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = self.configuration.copy() as! URLSessionConfiguration
                configuration.timeoutIntervalForRequest = 60
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                if let resume = try? Data(contentsOf: resumeURL) {
                    resumed = true
                    task = session.downloadTask(withResumeData: resume)
                } else {
                    task = session.downloadTask(with: url)
                }
                task?.resume()
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }

    func cancel() {
        guard continuation != nil, !cancelling else { return }
        cancelling = true
        task?.cancel { data in
            Task { @MainActor in
                if let data { try? data.write(to: self.resumeURL, options: .atomic) }
                self.complete(.failure(CancellationError()))
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in self.onProgress(totalBytesWritten) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // URLSession removes its temporary URL as soon as this callback returns.
        let held = location.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        let result: Result<URL, Error> = Result {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else { throw ModelStoreError.httpStatus(status) }
            try FileManager.default.moveItem(at: location, to: held)
            return held
        }
        Task { @MainActor in
            do {
                let held = try result.get()
                defer { try? FileManager.default.removeItem(at: held) }
                guard !self.cancelling else { return }
                if FileManager.default.fileExists(atPath: self.destination.path) {
                    try FileManager.default.removeItem(at: self.destination)
                }
                try FileManager.default.moveItem(at: held, to: self.destination)
                try? FileManager.default.removeItem(at: self.resumeURL)
                self.complete(.success(()))
            } catch {
                // An HTTP error body is not part of the file; the resume state behind it is spent.
                if error is ModelStoreError { try? FileManager.default.removeItem(at: self.resumeURL) }
                self.complete(.failure(error))
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            guard !self.cancelling else { return }
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? data.write(to: self.resumeURL, options: .atomic)
            } else if self.resumed {
                // Rejected resume data (e.g. its temp file was purged) would fail the same way on every tap.
                try? FileManager.default.removeItem(at: self.resumeURL)
            }
            self.complete(.failure(error))
        }
    }

    private func complete(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
    }
}
