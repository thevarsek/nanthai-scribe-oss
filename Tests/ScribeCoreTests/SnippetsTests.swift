import Testing
@testable import ScribeCore

struct SnippetsTests {
    let signature = Snippet(trigger: "my signature", text: "Best,\nAlex")

    @Test func exactMatchIsVerbatim() {
        #expect(Snippets.exactMatch(in: "MY, signature!", snippets: [signature]) == "Best,\nAlex")
        #expect(Snippets.exactMatch(in: "my signatures", snippets: [signature]) == nil)
        #expect(Snippets.exactMatch(in: "...", snippets: [Snippet(trigger: "", text: "bad")]) == nil)
    }

    @Test func wholeWordsAndPunctuation() {
        #expect(Snippets.expand(in: "Add MY—signature, please. My signature!", snippets: [signature]) == "Add Best,\nAlex, please. Best,\nAlex!")
        #expect(Snippets.expand(in: "my signatures and notmy signature", snippets: [signature]) == "my signatures and notmy signature")
    }

    @Test func longestMatchAndNoRecursion() {
        let short = Snippet(trigger: "my", text: "short")
        let recursive = Snippet(trigger: "Best", text: "recursive")
        #expect(Snippets.expand(in: "my signature", snippets: [short, signature, recursive]) == "Best,\nAlex")
    }

    @Test func unicodeAndUnchangedSurroundings() {
        let snippet = Snippet(trigger: "café address", text: "  12 Rue\nParis  ")
        #expect(Snippets.expand(in: "Hello: CAFÉ, address! Bye.", snippets: [snippet]) == "Hello:   12 Rue\nParis  ! Bye.")
        #expect(Snippets.expand(in: "untouched 👋\n", snippets: []) == "untouched 👋\n")
    }
}
