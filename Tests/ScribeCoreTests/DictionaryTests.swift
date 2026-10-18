import Foundation
import Testing
@testable import ScribeCore

@Suite struct DictionaryTests {
    private let dictionary = [
        DictionaryEntry(term: "NanthAi", variants: ["nant", "nanth ai"]),
        DictionaryEntry(term: "Nanth", variants: ["nanth"]),
        DictionaryEntry(term: "Niccolò", variants: ["nicolo"]),
        DictionaryEntry(term: "Società", variants: ["societa"])
    ]

    @Test func wordBoundariesAndPossessives() {
        let text = "nant Nantes nanths nanth's nanth’s NANT nanth2 2nanth énanth nanthé"
        #expect(DictionaryReplacement.apply(to: text, dictionary: dictionary)
            == "NanthAi Nantes nanths Nanth's Nanth’s NanthAi nanth2 2nanth énanth nanthé")
    }

    @Test func italianUnicodeAndCombiningMarks() {
        #expect(TextCleanup.clean("nicolo lavora per la societa, perché?", dictionary: dictionary)
            == "Niccolò lavora per la Società, perché?")
        let accents = [DictionaryEntry(term: "PERCHÉ", variants: ["perche"])]
        #expect(DictionaryReplacement.apply(to: "perche perché perché percheria xperche perche2", dictionary: accents)
            == "PERCHÉ PERCHÉ PERCHÉ percheria xperche perche2")
        #expect(DictionaryReplacement.apply(to: "società SOCIETÀ societa", dictionary: dictionary)
            == "Società Società Società")
        #expect(DictionaryReplacement.apply(to: "perchéperche percheperché 2perche perche² perché?", dictionary: accents)
            == "perchéperche percheperché 2perche perche² PERCHÉ?")
    }

    @Test func longestMatchWhitespaceAndCaseNormalization() {
        #expect(DictionaryReplacement.apply(to: "NANTH AI nanth\t ai nanth\nai nanthai", dictionary: dictionary)
            == "NanthAi NanthAi NanthAi NanthAi")
        let overlap = [DictionaryEntry(term: "A", variants: ["one two"]),
                       DictionaryEntry(term: "B", variants: ["two three four"])]
        #expect(DictionaryReplacement.apply(to: "one two three four", dictionary: overlap) == "one B")
    }

    @Test func replacementIsLiteralNonrecursiveAndIgnoresBlankTerms() {
        let entries = [DictionaryEntry(term: "second", variants: ["first"]),
                       DictionaryEntry(term: "third", variants: ["second"]),
                       DictionaryEntry(term: "  \n", variants: ["keep"]),
                       DictionaryEntry(term: "$1\\term", variants: ["cash"])]
        #expect(DictionaryReplacement.apply(to: "first keep cash", dictionary: entries) == "second keep $1\\term")
    }

    @Test func variantParsingSharedByEditors() {
        #expect(DictionaryEntry.parseVariants(" nant, , NANT, nanth ai, NanthAi,\n nanth ai , à, À, a ", term: " NanthAi ")
            == ["nant", "nanth ai", "à", "a"])
        #expect(DictionaryEntry.parseVariants(" , \n", term: "") == [])
        #expect(DictionaryEntry.parseVariants("Straße, STRASSE, ς, Σ", term: "word") == ["Straße", "ς"])
    }

    @Test func contextualStringsAreDictionaryFirstDeduplicatedAndBounded() {
        let entries = [DictionaryEntry(term: "NanthAi"), DictionaryEntry(term: "  "), DictionaryEntry(term: "NANTHAI")]
        let screen = ["nanthai", "Screen"] + (0..<120).map { "term\($0)" }
        let context = DictionaryEntry.contextualStrings(in: entries, screenTerms: screen)
        #expect(context.count == 100)
        #expect(Array(context.prefix(3)) == ["NanthAi", "Screen", "term0"])
    }
}
