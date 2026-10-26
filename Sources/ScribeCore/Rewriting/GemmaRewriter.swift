import Foundation
import Metal
import MLX
import MLXLLM
import MLXLMCommon

/// A warm, local-only Gemma model; each rewrite gets a fresh chat session.
public actor GemmaRewriter: TextRewriter {
    public nonisolated let id = "gemma-4-e2b"
    private let modelDirectory: URL
    private let timeout: Duration
    private var model: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var memoryPressure: MemoryPressureMonitor?
    private var generation = 0

    public init(modelDirectory: URL, timeout: Duration = .seconds(30)) {
        self.modelDirectory = modelDirectory
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        guard ModelStore.isInstalled(ModelCatalog.gemma, at: modelDirectory) else { return false }
        do { _ = try await load(); return true } catch { return false }
    }

    public func rewrite(_ request: RewriteRequest) async throws -> String {
        guard ModelStore.isInstalled(ModelCatalog.gemma, at: modelDirectory) else {
            throw RewriteError.unavailable("Download Gemma 4 first.")
        }
        let timeout = self.timeout
        let output = try await RewriteDeadline.run(timeout: timeout) {
            let model = try await self.load()
            try Task.checkCancellation()
            let session = ChatSession(model, instructions: RewritePrompts.instructions(for: request),
                                      generateParameters: .init(maxTokens: 2_000, temperature: 0.3),
                                      additionalContext: ["enable_thinking": false])
            let output = try await session.respond(to: RewritePrompts.prompt(for: request))
            try Task.checkCancellation()
            return output
        }
        return try RewriteGuard.validate(output, for: request)
    }

    /// Meeting prompts are separate from the dictation rewrite contract.
    public func meetingSummary(_ source: String, partial: Bool) async throws -> String {
        guard ModelStore.isInstalled(ModelCatalog.gemma, at: modelDirectory) else {
            throw RewriteError.unavailable("Download Gemma 4 first.")
        }
        let model = try await load()
        try Task.checkCancellation()
        let session = ChatSession(model,
            instructions: MeetingSummaryPrompts.instructions + "\n" + MeetingSummaryPrompts.jsonInstructions,
            generateParameters: .init(maxTokens: 2_000, temperature: 0),
            additionalContext: ["enable_thinking": false])
        let result = try await session.respond(to: MeetingSummaryPrompts.prompt(source, partial: partial))
        try Task.checkCancellation()
        return result
    }

    public func unload() {
        generation += 1
        let wasLoaded = model != nil
        model = nil
        // An in-flight generation owns its model until it finishes. Don't interrupt dictation.
        if wasLoaded, loading == nil { Memory.clearCache() }
    }

    private func load() async throws -> ModelContainer {
        // A cancelled iOS rewrite may reach the actor after its background unload.
        // Do not start (or retain) a fresh GPU model for that stale request.
        try Task.checkCancellation()
        if let model { return model }
        if let loading { return try await loading.value }
        guard MTLCreateSystemDefaultDevice() != nil, Self.prepareMetalLibrary() else {
            throw RewriteError.unavailable("Gemma needs a Metal device and MLX's compiled Metal library. Build with Xcode; see Tools/README.md.")
        }
        if memoryPressure == nil {
            memoryPressure = MemoryPressureMonitor { [weak self] in Task { await self?.unload() } }
        }
        let directory = modelDirectory
        let currentGeneration = generation
        let task = Task {
            try await LLMModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
        }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value
        if currentGeneration == generation { model = loaded }
        return loaded
    }

    /// Fail with a recoverable error instead of letting MLX abort when a SwiftPM-only
    /// executable has no compiled shaders. Mirrors MLX's documented bundle locations.
    public static func prepareMetalLibrary() -> Bool {
        if let library = GPU.metallib, FileManager.default.fileExists(atPath: library.path) { return true }
        let executable = Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL
        var roots = [Bundle.main.bundleURL, Bundle.main.resourceURL ?? executable, executable]
        roots += (ProcessInfo.processInfo.environment["DYLD_FRAMEWORK_PATH"] ?? "").split(separator: ":").map { URL(filePath: String($0)) }
        roots += Bundle.allBundles.compactMap(\.resourceURL)
        for root in roots {
            for path in ["mlx.metallib", "default.metallib", "mlx-swift_Cmlx.bundle/default.metallib", "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"] {
                let library = root.appending(path: path)
                if FileManager.default.fileExists(atPath: library.path) {
                    // Native SwiftPM app packaging puts shaders in Contents/Resources.
                    // Give MLX the exact path before its first GPU operation.
                    GPU.metallib = library
                    return true
                }
            }
        }
        return false
    }
}

private final class MemoryPressureMonitor: @unchecked Sendable {
    private let source: any DispatchSourceMemoryPressure
    init(handler: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler(handler: handler)
        source.resume()
    }
    deinit { source.cancel() }
}
