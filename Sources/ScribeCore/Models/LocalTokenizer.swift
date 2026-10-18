import Foundation
import MLXLMCommon
import Tokenizers

/// The only tokenizer entry point accepts a local folder. It cannot resolve a Hub ID.
/// Tokenizers internally links Hub, but this local overload reads JSON/Jinja from disk.
struct LocalTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        let template = try String(contentsOf: directory.appending(path: "chat_template.jinja"), encoding: .utf8)
        return LocalTokenizer(upstream: tokenizer, template: template)
    }
}

private struct LocalTokenizer: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    let template: String
    func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }
    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        try upstream.applyChatTemplate(messages: messages, chatTemplate: .literal(template), addGenerationPrompt: true, truncation: false, maxLength: nil, tools: tools,
                                       additionalContext: additionalContext)
    }
}
