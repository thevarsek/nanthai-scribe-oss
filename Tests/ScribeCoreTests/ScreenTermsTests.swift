import Testing
@testable import ScribeCore

@Suite struct ScreenTermsTests {
    @Test func englishNamesAndSentenceStarts() {
        let terms = ScreenTerms.extract(from: "Please send this to Ada Lovelace at Nanthai. Please send it today. The plan is ready. The plan will ship.")
        #expect(terms.contains("Ada Lovelace"))
        #expect(terms.contains("Nanthai"))
        #expect(!terms.contains("Please"))
        #expect(!terms.contains("The"))
    }

    @Test func loneSentenceInitialCommonWordsDoNotBecomeHints() {
        let terms = ScreenTerms.extract(from: "Tomorrow we will meet. Afterwards we can review. Someone will send notes. Sofia: We can ship. Use AX for M3.")
        #expect(!terms.contains("Tomorrow"))
        #expect(!terms.contains("Afterwards"))
        #expect(!terms.contains("Someone"))
        #expect(!terms.contains("We"))
        #expect(terms.contains("AX"))
    }

    @Test func italianAndAccentedNames() {
        let terms = ScreenTerms.extract(from: "Grazie per il messaggio. Scrivi a Niccolò Okafor e José Álvarez per Nanthai.")
        #expect(terms.contains("Niccolò Okafor"))
        #expect(terms.contains("José Álvarez"))
        #expect(!terms.contains("Grazie"))
    }

    @Test func germanNounsRemainUsefulWithoutTreatingEveryCapitalAsAName() {
        let terms = ScreenTerms.extract(from: "Der Bericht von Jürgen Müller betrifft die Entwicklung. Der Bericht enthält das Projekt M3.")
        #expect(terms.contains("Jürgen Müller"))
        #expect(terms.contains("Bericht"))
        #expect(terms.contains("Entwicklung"))
        #expect(!terms.contains("Der"))
        #expect(terms.contains("M3"))
    }

    @Test func japaneseDoesNotRequireCapitalization() {
        let terms = ScreenTerms.extract(from: "田中さんは東京で会議。@たなか と #新製品 の iOS26 と M3 を確認。")
        #expect(terms.contains("@たなか"))
        #expect(terms.contains("#新製品"))
        #expect(terms.contains("iOS26"))
        #expect(terms.contains("M3"))
    }

    @Test func structuredTermsAndCaseInsensitiveDedupe() {
        let text = "Contact josé@example.it or @Nanthai about #Scribe, screenCard, LiveTranscriber and M3. @nanthai uses screenCard."
        let terms = ScreenTerms.extract(from: text)
        for term in ["josé@example.it", "@Nanthai", "#Scribe", "screenCard", "LiveTranscriber", "M3"] {
            #expect(terms.contains(term))
        }
        #expect(terms.filter { $0.lowercased() == "@nanthai" }.count == 1)
    }

    @Test func hundredTermCapAndDeterminism() {
        let text = (0..<180).map { "identifier\($0)" }.joined(separator: " ")
        let terms = ScreenTerms.extract(from: text)
        #expect(terms.count == 100)
        #expect(terms == ScreenTerms.extract(from: text))
        #expect(Set(terms).count == terms.count)
    }

    @Test func ranksCursorThenFrequency() throws {
        let near = "cursorTerm " + String(repeating: "plain ", count: 100) + "distantTerm"
        let terms = ScreenTerms.extract(from: "frequentTerm frequentTerm frequentTerm uniqueTerm", nearCursor: near, cursorOffset: 0)
        #expect(terms.first == "cursorTerm")
        #expect(try #require(terms.firstIndex(of: "frequentTerm")) < #require(terms.firstIndex(of: "uniqueTerm")))
        #expect(try #require(terms.firstIndex(of: "distantTerm")) < #require(terms.firstIndex(of: "frequentTerm")))
    }

    @Test func cursorWindowUsesCharactersAndClampsBounds() {
        let text = String(repeating: "🙂", count: 4_000)
        #expect(ScreenTerms.nearCursor(in: text, offset: 2_000).count == 3_000)
        #expect(ScreenTerms.nearCursor(in: text, offset: -1).count == 1_500)
        #expect(ScreenTerms.nearCursor(in: text, offset: 9_000).count == 1_500)
        #expect(ScreenTerms.nearCursor(in: "", offset: 0).isEmpty)
    }
}
