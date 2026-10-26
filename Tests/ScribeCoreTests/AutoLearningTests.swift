import Foundation
import Testing
@testable import ScribeCore

@Suite struct CorrectionDetectorTests {
    @Test func spellingAndName() {
        #expect(CorrectionDetector.candidate(inserted: "Ask Nantai tomorrow.", current: "Ask NanthAi tomorrow.") == CorrectionPair(heard: "Nantai", meant: "NanthAi"))
        #expect(CorrectionDetector.candidate(inserted: "ask the person", current: "ask Jo person") == CorrectionPair(heard: "the", meant: "Jo"))
        #expect(CorrectionDetector.candidate(inserted: "hello jon", current: "hello John") != nil)
        #expect(CorrectionDetector.candidate(inserted: "say sean", current: "say Shawn") != nil)
        #expect(CorrectionDetector.candidate(inserted: "ciao nicolo", current: "ciao Niccolò") != nil)
        #expect(CorrectionDetector.candidate(inserted: "привет катя", current: "привет Катя") != nil)
        #expect(CorrectionDetector.candidate(inserted: "meet nan tai today", current: "meet nanth ai today") != nil)
        #expect(CorrectionDetector.candidate(inserted: "go to san fran sisco", current: "go to San Fran Cisco") != nil)
        #expect(CorrectionDetector.candidate(inserted: "hello jon!", current: "hello John.") != nil)
    }
    @Test func onlyOneReplacementOfOneToThreeWords() {
        #expect(CorrectionDetector.candidate(inserted: "good morrning", current: "good morning") != nil)
        #expect(CorrectionDetector.candidate(inserted: "tomorow then Nantai", current: "tomorrow then NanthAi") == nil)
        #expect(CorrectionDetector.candidate(inserted: "one two three four", current: "Onee Twoo Threee Fourr") == nil)
        #expect(CorrectionDetector.candidate(inserted: "Nantai at 12", current: "NanthAi at 13") == nil)
        #expect(CorrectionDetector.candidate(inserted: "make the thing", current: "write a novel") == nil)
    }
    @Test func ignoresNonCorrections() {
        for (old, new) in [("hi there", "hi, there!"), ("hi there", "hi  there"), ("hi there", "hi"), ("hi", "hi there"),
                           ("take 12", "take 13"), ("v12", "v13"), ("hi there", "hi there")] {
            #expect(CorrectionDetector.candidate(inserted: old, current: new) == nil)
        }
        let pair = CorrectionPair(heard: "Nantai", meant: "NanthAi")
        #expect(CorrectionDetector.candidate(inserted: pair.heard, current: pair.meant, dictionary: pair.adding(to: [])) == nil)
    }
    @Test func extensionPreservesVariantsAndMarksLearning() {
        let entry = DictionaryEntry(term: "NanthAi", variants: ["nant"], source: .user)
        let pair = CorrectionPair(heard: "Nantai", meant: "NanthAi")
        let result = pair.adding(to: pair.adding(to: [entry]))
        #expect(result.count == 1)
        #expect(result[0].source == .learned)
        #expect(result[0].variants == ["nant", "Nantai"])
        #expect(pair.adding(to: [])[0].source == .learned)
        let casing = CorrectionPair(heard: "Nanthai", meant: "NanthAi")
        let oldCasing = [DictionaryEntry(term: "Nanthai", variants: ["nant"])]
        #expect(CorrectionDetector.candidate(inserted: casing.heard, current: casing.meant, dictionary: oldCasing) == casing)
        let corrected = casing.adding(to: oldCasing)
        #expect(corrected[0].term == "NanthAi")
        #expect(corrected[0].variants == ["nant"])
        #expect(DictionaryReplacement.apply(to: "Nanthai", dictionary: corrected) == "NanthAi")
        let shadowed = [DictionaryEntry(term: "Nantai"), DictionaryEntry(term: "NanthAi", variants: ["nant"])]
        #expect(DictionaryReplacement.apply(to: "Nantai", dictionary: pair.adding(to: shadowed)) == "NanthAi")
        #expect(DictionaryReplacement.apply(to: "Nantai", dictionary: pair.adding(to: [shadowed[0]])) == "NanthAi")
    }
    @Test func spansExpireAndLoseAnchors() {
        let now = Date(timeIntervalSince1970: 100)
        let span = CorrectionSpan(inserted: "Nantai", prefix: "hi ", suffix: " there", at: now)
        #expect(span.current(in: "hi NanthAi there", at: now.addingTimeInterval(60)) == "NanthAi")
        #expect(span.current(in: "hi NanthAi there", at: now.addingTimeInterval(61)) == nil)
        #expect(span.current(in: "hey NanthAi there", at: now) == nil)
        #expect(span.current(in: "hi NanthAi", at: now) == nil)
    }
}

@Suite struct CorrectionPolicyTests {
    let pair = CorrectionPair(heard: "Nantai", meant: "NanthAi")
    let now = Date(timeIntervalSince1970: 100)
    @Test func firstThenThreeMoreThenIgnored() {
        var log = CorrectionLog()
        #expect(log.record(pair, at: now, canAsk: true) == true)
        log.notNow(pair)
        #expect(log.record(pair, at: now.addingTimeInterval(600), canAsk: true) == false)
        #expect(log.record(pair, at: now.addingTimeInterval(1_200), canAsk: true) == false)
        #expect(log.record(pair, at: now.addingTimeInterval(1_800), canAsk: true) == true)
        log.notNow(pair)
        for index in 1...5 { #expect(log.record(pair, at: now.addingTimeInterval(Double(index) * 3_600), canAsk: true) == false) }
        #expect(log.entries[0].state == .ignored)
        #expect(log.entries[0].timesSeen == 9)
        log.forget(pair)
        #expect(log.entries.isEmpty)
        #expect(log.record(pair, at: now.addingTimeInterval(30_000), canAsk: true) == true)
    }
    @Test func cooldownAcrossPairsAndUnavailableSurface() {
        var log = CorrectionLog()
        #expect(log.record(pair, at: now, canAsk: false) == false)
        #expect(log.entries[0].state == .suggested)
        #expect(log.lastPrompt == nil)
        #expect(log.record(pair, at: now, canAsk: true) == true)
        let other = CorrectionPair(heard: "nicolo", meant: "Niccolò")
        #expect(log.record(other, at: now.addingTimeInterval(599), canAsk: true) == false)
        #expect(log.record(other, at: now.addingTimeInterval(600), canAsk: true) == true)
        #expect(log.newestFirst.first?.pair == other)
        log.ignore(other)
        #expect(log.record(other, at: now.addingTimeInterval(1_200), canAsk: true) == false)
    }
    @Test func policySurvivesRoundTrip() throws {
        var log = CorrectionLog()
        _ = log.record(pair, at: now, canAsk: true)
        log.notNow(pair)
        #expect(try JSONDecoder().decode(CorrectionLog.self, from: JSONEncoder().encode(log)) == log)
    }
}

@Suite struct NameMatcherTests {
    @Test func matchingOnlyAndTenAtMost() {
        let names = ["John", "Shawn", "Niccolò", "Zqxv", "John"]
        let result = NameMatcher.matches(in: "jon called sean and nicolo", names: names)
        #expect(Set(result.map(\.term)) == Set(["John", "Shawn", "Niccolò"]))
        #expect(NameMatcher.matches(in: "", names: names).isEmpty)
        #expect(NameMatcher.matches(in: "go to", names: ["Jo"]).isEmpty)
        let thirty = "aeiou".flatMap { vowel in ["", "a", "e", "i", "o", "u"].map { "J\(vowel)n\($0)" } }
        #expect(NameMatcher.matches(in: "jon", names: thirty).count == 10)
        #expect(NameMatcher.matches(in: "привет катя", names: ["Катя"]).first?.term == "Катя")
    }
    @Test func onlyEphemeralReplacement() {
        let matches = NameMatcher.matches(in: "ask jon", names: ["John", "Zqxv"])
        #expect(DictionaryReplacement.apply(to: "ask jon", dictionary: matches) == "ask John")
        #expect(matches.flatMap(\.variants) == ["jon"])
    }
}

/// The owner's iPhone, with "Use names from Contacts" on, turned these words into contacts.
@Suite struct NameMatcherCommonWordTests {
    static let contacts = ["Andy", "Mara", "Dave", "Jake", "Linsey", "Donna", "Farah", "Alain", "Falso", "Ally",
                           "Giulia", "Shawn", "Marc", "De Luca", "Anna Maria"]
    /// Stands in for the spell checker: ordinary English and Italian words, lowercased.
    static let lexicon: Set<String> = [
        "and", "more", "have", "make", "lines", "done", "far", "again", "also", "really", "all", "mark",
        "i", "we", "need", "to", "the", "so", "it", "is", "a", "question", "met", "today", "called", "said",
        "ho", "parlato", "con", "ieri", "e", "ma", "fare", "anche", "domani", "di", "chiamo", "sono", "stata", "da",
    ]
    static func isWord(_ word: String) -> Bool { lexicon.contains(word) }
    static func replaced(_ text: String) -> String {
        DictionaryReplacement.apply(to: text, dictionary: NameMatcher.matches(in: text, names: contacts, isWord: isWord))
    }

    @Test(arguments: [("and", "Andy"), ("more", "Mara"), ("have", "Dave"), ("make", "Jake"), ("lines", "Linsey"),
                      ("done", "Donna"), ("far", "Farah"), ("again", "Alain"), ("also", "Falso"), ("really", "Ally")])
    func ownerPairsNeverMatch(word: String, name: String) {
        for text in ["we said \(word) it is", "\(word.prefix(1).uppercased() + word.dropFirst()) it is.", "so. \(word.prefix(1).uppercased() + word.dropFirst()) we", word] {
            #expect(NameMatcher.matches(in: text, names: [name], isWord: Self.isWord).isEmpty, "\(text) → \(name)")
        }
    }
    @Test func ownerSentenceIsUntouched() {
        let text = "I have to make more lines and also really get it done again so far all is fine"
        #expect(Self.replaced(text) == text)
        #expect(Self.replaced("ho parlato con chiara e anche ma fare domani") == "ho parlato con chiara e anche ma fare domani")
    }
    /// Without a spell checker, the tagger still keeps function words ("and", "e", "di") out.
    @Test func functionWordsNeedNoLexicon() {
        #expect(NameMatcher.matches(in: "we need this and that", names: ["Andy"]).isEmpty)
        #expect(NameMatcher.matches(in: "parlo di te e di lui", names: ["Dino", "Eva"]).isEmpty)
    }
    @Test func misheardNamesStillFixed() {
        #expect(Self.replaced("I called sean today") == "I called Shawn today")
        #expect(Self.replaced("ho parlato con julia ieri") == "ho parlato con Giulia ieri")
        #expect(Self.replaced("ho parlato con Julia ieri") == "ho parlato con Giulia ieri")
        #expect(Self.replaced("Julia called today") == "Giulia called today")
        #expect(Self.replaced("domani chiamo ana maria") == "domani chiamo Anna Maria")
        #expect(Self.replaced("sono stata da de luka ieri") == "sono stata da De Luca ieri")
        #expect(Self.replaced("I met andie today") == "I met Andy today")
    }
    /// The recogniser's capital mid-sentence marks a proper noun, but replacement is global, so a
    /// lowercase "mark" elsewhere vetoes it.
    @Test func capitalisedWordOnlyWhenEveryOccurrenceIs() {
        #expect(Self.replaced("I met Mark today") == "I met Marc today")
        #expect(Self.replaced("Mark called today") == "Mark called today")
        #expect(Self.replaced("I met Mark today, question mark") == "I met Mark today, question mark")
    }
    @Test func stricterSimilarity() {
        #expect(NameMatcher.sounds("also", like: "Falso", score: CorrectionDetector.similarity("also", "Falso")) == false)
        #expect(NameMatcher.sounds("again", like: "Alain", score: CorrectionDetector.similarity("again", "Alain")) == false)
        #expect(NameMatcher.sounds("jon", like: "John", score: CorrectionDetector.similarity("jon", "John")))
    }
}

@Suite struct KeyboardWordsTests {
    @Test func twoKeepsManualRemoveReset() {
        var words = KeyboardWords()
        #expect(words.keep("NanthAi") == false)
        #expect(words.words.isEmpty)
        #expect(words.keep("nanthai") == true)
        #expect(words.words == ["NanthAi"])
        #expect(words.keep("NanthAi") == false)
        words.add("Scribe")
        #expect(words.words.count == 2)
        words.remove("NANTHAI")
        #expect(words.words == ["Scribe"])
        words.reset()
        #expect(words.observations.isEmpty)
    }
    @Test func storeRereadsAndDoesNotOverwriteCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = LearningStore(directory: root), second = LearningStore(directory: root)
        try first.transaction { _ = $0.keyboard.keep("NanthAi") }
        try second.transaction { _ = $0.keyboard.keep("NanthAi") }
        #expect(try first.load().keyboard.words == ["NanthAi"])
        let url = root.appending(path: "learning.json")
        let bad = Data("broken".utf8)
        try bad.write(to: url)
        #expect(throws: (any Error).self) { try first.transaction { $0.keyboard.add("other") } }
        #expect(try Data(contentsOf: url) == bad)
    }
    @Test @MainActor func queuedDictionaryMergeIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let learning = LearningModel(directory: root)
        let vocabulary = Vocabulary(directory: root)
        let pair = CorrectionPair(heard: "Nantai", meant: "NanthAi")
        learning.update { $0.pendingDictionary.append(pair) }
        learning.mergePending(into: vocabulary)
        learning.mergePending(into: vocabulary)
        #expect(vocabulary.dictionary.count == 1)
        #expect(vocabulary.dictionary[0].variants == ["Nantai"])
        #expect(learning.document.pendingDictionary.isEmpty)
    }
}
