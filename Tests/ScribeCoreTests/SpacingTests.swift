import Testing
@testable import ScribeCore

@Suite struct SpacingTests {
    @Test func addsSpaceAfterSentence() { #expect(Spacing.needsLeadingSpace(before: ".", inserting: "Next one.")) }
    @Test func addsSpaceAfterWord() { #expect(Spacing.needsLeadingSpace(before: "o", inserting: "world")) }
    @Test func noSpaceAtStart() { #expect(!Spacing.needsLeadingSpace(before: nil, inserting: "Hi")) }
    @Test func noSpaceAfterSpaceOrNewline() {
        #expect(!Spacing.needsLeadingSpace(before: " ", inserting: "Hi"))
        #expect(!Spacing.needsLeadingSpace(before: "\n", inserting: "Hi"))
    }
    @Test func noSpaceAfterOpeningBracket() { #expect(!Spacing.needsLeadingSpace(before: "(", inserting: "aside")) }
    @Test func noSpaceBeforePunctuation() { #expect(!Spacing.needsLeadingSpace(before: "d", inserting: ", then")) }
}
