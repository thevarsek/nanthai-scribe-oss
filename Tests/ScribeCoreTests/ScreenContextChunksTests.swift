import Testing
@testable import ScribeCore

@Suite struct ScreenContextChunksTests {
    @Test func tokenEstimate() {
        #expect(ScreenContextChunks.estimatedTokens("abcd") == 1)
        #expect(ScreenContextChunks.estimatedTokens("abcde") == 2)
        #expect(ScreenContextChunks.estimatedTokens("日本語かなカナ한국") == 9)
        #expect(ScreenContextChunks.estimatedTokens("abcd日本") == 3)
    }

    @Test func asciiAndCJKStayWithinBudget() {
        for text in [String(repeating: "a", count: 25_000), String(repeating: "東京の会議。", count: 2_000)] {
            let chunks = ScreenContextChunks.chunks(text)
            #expect(chunks.count > 1)
            #expect(chunks.joined() == text)
            #expect(chunks.allSatisfy { ScreenContextChunks.estimatedTokens($0) <= 2_500 })
        }
    }

    @Test func boundariesPreserveWhitespaceAndGraphemes() {
        let text = String(repeating: "Caffè 👩🏽‍💻 日本語.\n", count: 2_000)
        let chunks = ScreenContextChunks.chunks(text, maximumTokens: 100)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { ScreenContextChunks.estimatedTokens($0) <= 100 })
        #expect(chunks.dropLast().allSatisfy { $0.last?.isWhitespace == true })
        #expect(ScreenContextChunks.chunks("").isEmpty)
        #expect(ScreenContextChunks.chunks(text, maximumTokens: 0).isEmpty)
        #expect(ScreenContextChunks.chunks(String(repeating: "a", count: 10_000)).count == 1)
    }

    @Test func fallbackKeepsTextClosestToCursor() {
        let text = String(repeating: "x", count: 1_400) + "BEFORE|AFTER" + String(repeating: "y", count: 1_400)
        let card = ContextDistiller.fallback(terms: ["Nanthai"], nearCursor: text, cursorOffset: 1_407)
        #expect(card.contains("BEFORE|AFTER"))
        #expect(card.contains("Nanthai"))
        #expect(card.count <= 1_200)
        #expect(ScreenContextChunks.estimatedTokens(card) <= 300)
    }

    @Test func fallbackAndTruncationRespectBothBudgets() {
        let card = ContextDistiller.fallback(terms: (0..<100).map { "長い名前\($0)" }, nearCursor: String(repeating: "日本語", count: 1_000))
        #expect(card.count <= 1_200)
        #expect(ScreenContextChunks.estimatedTokens(card) <= 300)
        #expect(card.contains("Near cursor:"))
        #expect(card.contains("日本語"))
        #expect(ScreenContextChunks.truncate("abcd日本語", tokens: 2) == "abcd日")
    }
}
