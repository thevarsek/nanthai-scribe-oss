import Foundation
import FoundationModels

/// Rewriter backed by Apple's on-device Foundation Models (Apple Intelligence devices).
public struct AppleRewriter: TextRewriter {
    public let id = "apple"
    private let timeout: Duration

    public init(timeout: Duration = .seconds(20)) {
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Why the model can't run, for settings UI; nil when available.
    public static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings to use Refine."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading its model."
        case .unavailable: "Apple Intelligence isn't available."
        }
    }

    public func rewrite(_ request: RewriteRequest) async throws -> String {
        guard request.task == .polish, request.allowsSpokenNote else { return try await run(request) }
        // The small model misses notes like "make this an email" inside a brain dump. Split the
        // note out first, then run it as an explicit instruction over the rest.
        let split = try? await withTimeout {
            try await LanguageModelSession(instructions: RewritePrompts.noteSplitInstructions)
                .respond(to: RewritePrompts.noteSplitPrompt(request.transcript), generating: SpokenNote.self,
                         options: GenerationOptions(temperature: 0)).content
        }
        guard let split, let note = RewritePrompts.usableNote(split.note, content: split.content, transcript: request.transcript) else {
            return try await run(request)
        }
        var edited = request
        edited.task = .edit(instruction: note, selection: split.content)
        let text = try await run(edited)
        // Judge length against the dictation, as for any polish.
        return try RewriteGuard.validate(text, for: request)
    }

    private func withTimeout<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let timeout = self.timeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask { try await Task.sleep(for: timeout); throw RewriteError.timedOut }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw RewriteError.timedOut }
            return first
        }
    }

    private func run(_ request: RewriteRequest) async throws -> String {
        guard await isAvailable() else {
            throw RewriteError.unavailable(Self.unavailableReason ?? "Apple Intelligence isn't available.")
        }
        let instructions = RewritePrompts.instructions(for: request)
        let prompt = RewritePrompts.prompt(for: request)
        let output = try await withTimeout {
            try await LanguageModelSession(instructions: instructions).respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 2_000)
            ).content
        }
        return try RewriteGuard.validate(output, for: request)
    }
}

@Generable
struct SpokenNote {
    @Guide(description: "The speaker's note on how to write the text (format, tone, length, or language), word for word. Empty if there is none.")
    var note: String
    @Guide(description: "The rest of the dictation, word for word, without the note.")
    var content: String
}
