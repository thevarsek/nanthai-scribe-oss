import Foundation

/// Sentence and paragraph boundaries keep each model request small without truncating text.
public enum RefineChunks {
    public static func split(_ text: String, limit: Int = 2_500) -> [String] {
        precondition(limit > 0)
        var remaining = text[...]
        var chunks: [String] = []
        while remaining.count > limit {
            let end = remaining.index(remaining.startIndex, offsetBy: limit)
            let window = remaining[..<end]
            let paragraph = window.lastIndex(of: "\n").map { window.index(after: $0) }
            let sentence = window.indices.last { index in
                ".!?。！？".contains(window[index]) &&
                    (window.index(after: index) == window.endIndex || window[window.index(after: index)].isWhitespace)
            }.map { window.index(after: $0) }
            let word = window.lastIndex(where: \.isWhitespace).map { window.index(after: $0) }
            // DESIGN: Prefer a natural boundary in the latter half; hard-split unbroken text.
            let midpoint = remaining.index(remaining.startIndex, offsetBy: limit / 2)
            let boundary = [paragraph, sentence, word].compactMap { $0 }.first { $0 >= midpoint } ?? end
            chunks.append(String(remaining[..<boundary]))
            remaining = remaining[boundary...]
        }
        if !remaining.isEmpty { chunks.append(String(remaining)) }
        return chunks
    }
}

/// A failed chunk keeps its cleaned speech; other chunks still get refined.
public struct ChunkedRewriter: TextRewriter {
    private let base: any TextRewriter
    public var id: String { base.id }

    public init(_ base: any TextRewriter) { self.base = base }
    public func isAvailable() async -> Bool { await base.isAvailable() }

    public func rewrite(_ request: RewriteRequest) async throws -> String {
        guard request.task == .polish, request.transcript.count > 2_500 else {
            return try await base.rewrite(request)
        }
        var result = ""
        for (index, chunk) in RefineChunks.split(request.transcript).enumerated() {
            var part = request
            part.transcript = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            part.allowsSpokenNote = index == 0 && request.allowsSpokenNote
            let chunkRequest = part
            let cleaned = TextCleanup.clean(part.transcript)
            let output: String
            do {
                output = try await RewriteDeadline.run(timeout: .seconds(20)) { [base] in
                    try await base.rewrite(chunkRequest)
                }
            } catch { output = cleaned }
            let leading = String(chunk.prefix(while: \.isWhitespace))
            let trailing = String(chunk.reversed().prefix(while: \.isWhitespace).reversed())
            if !result.isEmpty, leading.isEmpty, !result.last!.isWhitespace { result += " " }
            result += leading + (output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleaned : output) + trailing
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
