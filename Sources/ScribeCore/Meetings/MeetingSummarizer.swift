import Foundation
import FoundationModels

@Generable
private struct GeneratedMeetingAction {
    @Guide(description: "Future work someone explicitly promised to do, as a concise verb phrase. Exclude statements, budget decisions, launch dates and completed work.") var text: String
    @Guide(description: "Owner only when explicitly stated; otherwise nil.") var owner: String?
}
@Generable
private struct GeneratedMeetingSummary {
    @Guide(description: "Every explicit follow-up task. A decision or factual statement is not a task. Empty if nobody commits to future work.") var actions: [GeneratedMeetingAction]
    @Guide(description: "One to six concise factual summary bullets; fewer for short meetings.", .count(1...6)) var bullets: [String]
}
@Generable
private struct GeneratedMeetingPart {
    @Guide(description: "Every explicit follow-up task. A decision or factual statement is not a task. Empty if nobody commits to future work.") var actions: [GeneratedMeetingAction]
    @Guide(description: "Detailed factual bullets covering every topic, decision, number, date and name in this part.", .count(1...12)) var bullets: [String]
}

public struct MeetingSummarizer: Sendable {
    private let gemma: GemmaRewriter?
    public init(gemma: GemmaRewriter? = nil) { self.gemma = gemma }

    public func summarize(_ meeting: Meeting) async throws -> MeetingSummary {
        guard !meeting.turns.isEmpty else { throw MeetingSummaryError.noTranscript }
        // Gemma's context budget leaves room for instructions and the response.
        let budget = gemma == nil ? 2_500 : 23_000
        var source = MeetingExport.transcript(meeting)
        while true {
            let chunks = MeetingSummaryPlan.chunks(source, maximumTokens: budget)
            if chunks.count == 1 { return try await generate(chunks[0], partial: false) }
            var partials: [MeetingSummary] = []
            for chunk in chunks {
                try Task.checkCancellation()
                partials.append(try await generate(chunk, partial: true))
            }
            source = try MeetingSummaryPlan.reduce(partials, previousSource: source)
        }
    }

    private func generate(_ source: String, partial: Bool) async throws -> MeetingSummary {
        if let gemma {
            return try MeetingSummaryParser.parse(await gemma.meetingSummary(source, partial: partial), partial: partial)
        }
        guard SystemLanguageModel.default.availability == .available else {
            throw RewriteError.unavailable(AppleRewriter.unavailableReason ?? "Apple Intelligence isn't available.")
        }
        let session = LanguageModelSession(instructions: MeetingSummaryPrompts.instructions)
        do {
            let prompt = MeetingSummaryPrompts.prompt(source, partial: partial)
            let summary: MeetingSummary
            if partial {
                let response = try await session.respond(to: prompt, generating: GeneratedMeetingPart.self,
                                                         options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 1_500))
                summary = .init(bullets: response.content.bullets,
                                actions: response.content.actions.map { .init(text: $0.text, owner: $0.owner) })
            } else {
                let response = try await session.respond(to: prompt, generating: GeneratedMeetingSummary.self,
                                                         options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 900))
                summary = .init(bullets: response.content.bullets,
                                actions: response.content.actions.map { .init(text: $0.text, owner: $0.owner) })
            }
            return try MeetingSummaryParser.validate(summary, partial: partial)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Actual tokenizer costs can exceed the estimate. Reduce recursively, retaining every part.
            let chunks = MeetingSummaryPlan.chunks(source, maximumTokens: max(1, MeetingSummaryPlan.estimatedTokens(source) / 2))
            guard chunks.count > 1, source.utf8.count > 300 else { throw MeetingSummaryError.didNotCompress }
            var parts: [String] = []
            for chunk in chunks { parts.append(MeetingSummaryPlan.source(try await generate(chunk, partial: true))) }
            let merged = parts.joined(separator: "\n")
            guard merged.utf8.count < source.utf8.count else { throw MeetingSummaryError.didNotCompress }
            return try await generate(merged, partial: partial)
        }
    }
}
