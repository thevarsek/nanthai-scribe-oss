import Testing
@testable import ScribeCore

@Suite struct TextCleanupTests {
    @Test func removesFillers() {
        #expect(TextCleanup.clean("Um, so I think, uh, we should ship it.") == "So I think, we should ship it.")
    }

    @Test func keepsWordsContainingFillers() {
        #expect(TextCleanup.clean("The umbrella is under the hummus.") == "The umbrella is under the hummus.")
    }

    @Test func trimsAndCollapsesSpaces() {
        #expect(TextCleanup.clean("  hello   world  ") == "Hello world")
    }

    @Test func emptyStaysEmpty() {
        #expect(TextCleanup.clean("  uh  ") == "")
    }
}
