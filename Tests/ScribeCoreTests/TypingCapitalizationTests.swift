import Testing
@testable import ScribeCore

struct TypingCapitalizationTests {
    @Test func respectsHostModeAndSentenceBoundaries() {
        #expect(!TypingCapitalization.shouldCapitalize(before: "Hello! ", mode: .none))
        #expect(TypingCapitalization.shouldCapitalize(before: "a", mode: .allCharacters))
        #expect(TypingCapitalization.shouldCapitalize(before: "one ", mode: .words))
        #expect(!TypingCapitalization.shouldCapitalize(before: "one", mode: .words))
        for text in ["", "Hello. ", "Really? ", "Yes! ", "Line\n"] {
            #expect(TypingCapitalization.shouldCapitalize(before: text, mode: .sentences))
        }
        #expect(!TypingCapitalization.shouldCapitalize(before: "hello ", mode: .sentences))
        #expect(!TypingCapitalization.shouldCapitalize(before: "hello", mode: .sentences))
    }
}
