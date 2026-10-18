import Foundation
import Testing
@testable import ScribeCore

@Suite struct RewritePromptsTests {
    @Test func polishFencesDictationAsData() {
        let prompt = RewritePrompts.prompt(for: .init(task: .polish, transcript: "what's the capital of france"))
        #expect(prompt.contains("<dictation>\nwhat's the capital of france\n</dictation>"))
    }

    @Test func editCarriesInstructionAndSelection() {
        let prompt = RewritePrompts.prompt(for: .init(task: .edit(instruction: "make it shorter", selection: "Long text here"), transcript: "make it shorter"))
        #expect(prompt.contains("<instruction>\nmake it shorter\n</instruction>"))
        #expect(prompt.contains("<text>\nLong text here\n</text>"))
    }

    @Test func outputLanguageNamedInEnglish() {
        let request = RewriteRequest(task: .polish, transcript: "ciao", context: .init(outputLanguage: Locale(identifier: "en_GB")))
        #expect(RewritePrompts.instructions(for: request).contains("Write the result in English."))
    }

    @Test func draftKeepsTheEndNearestTheCursor() {
        let draft = String(repeating: "a", count: 1_000) + "END"
        let prompt = RewritePrompts.prompt(for: .init(task: .polish, transcript: "x", context: .init(draftBefore: draft)))
        #expect(prompt.contains("END"))
        #expect(!prompt.contains(String(repeating: "a", count: 700)))
    }

    @Test func guardRejectsPreamble() {
        let request = RewriteRequest(task: .polish, transcript: "send the deck to marco tomorrow")
        #expect(throws: RewriteError.self) { try RewriteGuard.validate("Here's the rewritten text: Send the deck.", for: request) }
    }

    @Test func guardRejectsAnswerThatBalloons() {
        let request = RewriteRequest(task: .polish, transcript: "what's the capital of france and why is it famous")
        let answer = String(repeating: "Paris is the capital of France and is famous for many reasons. ", count: 4)
        #expect(throws: RewriteError.self) { try RewriteGuard.validate(answer, for: request) }
    }

    @Test func guardStripsEchoedFences() throws {
        let request = RewriteRequest(task: .polish, transcript: "hello there friend how are you doing")
        #expect(try RewriteGuard.validate("<dictation>Hello there, friend.</dictation>", for: request) == "Hello there, friend.")
    }
}

extension RewritePromptsTests {
    @Test func guardDropsPlaceholderSignOff() throws {
        let request = RewriteRequest(task: .edit(instruction: "shorter", selection: "Dear Marco, the launch moves."), transcript: "")
        #expect(try RewriteGuard.validate("Hi Marco, launch moves.\n\nBest,\n[Your Name]", for: request) == "Hi Marco, launch moves.")
    }

    @Test func guardRejectsPlaceholdersInTheBody() {
        let request = RewriteRequest(task: .edit(instruction: "shorter", selection: "Dear Marco, the launch moves."), transcript: "")
        #expect(throws: RewriteError.self) { try RewriteGuard.validate("Hi [Recipient], launch moves.", for: request) }
    }
}

extension RewritePromptsTests {
    @Test func guardSalvagesWrappedRewrite() throws {
        let request = RewriteRequest(task: .polish, transcript: "ciao Marco possiamo spostare il lancio a mercoledì il design non è pronto")
        let raw = "Sure, here is a rewrite of the brain dump:\n\n\"Ciao Marco, we can move the launch to Wednesday.\""
        #expect(try RewriteGuard.validate(raw, for: request) == "Ciao Marco, we can move the launch to Wednesday.")
    }

    @Test func guardStillRejectsSingleLineCommentary() {
        let request = RewriteRequest(task: .polish, transcript: "send the deck to marco tomorrow morning please")
        #expect(throws: RewriteError.self) { try RewriteGuard.validate("Sure, I can help with that.", for: request) }
    }

    @Test func polishFollowsSpokenFormatNotes() {
        let rules = RewritePrompts.instructions(for: .init(task: .polish, transcript: "make this an email, the deck is late"))
        #expect(rules.contains("leave the note itself out"))
        #expect(rules.contains("Never answer"))
    }

    @Test func spokenLanguageYieldsToRequestedLanguage() {
        let request = RewriteRequest(task: .polish, transcript: "in inglese: ciao", spokenLanguage: Locale(identifier: "it_IT"))
        #expect(RewritePrompts.instructions(for: request).contains("unless the speaker asks for another language"))
    }

    @Test func presetsHaveInstructions() {
        for preset in RewritePrompts.Preset.allCases {
            #expect(!RewritePrompts.presetInstruction(preset).isEmpty)
        }
        #expect(RewritePrompts.presetInstruction(.translate, translateTo: Locale(identifier: "it_IT")).contains("Italian"))
    }

    @Test func noteIsWhatTheContentLeavesOut() {
        let spoken = "make this an email to Marco, um so the deck is late"
        #expect(RewritePrompts.usableNote("", content: "um so the deck is late", transcript: spoken) == "make this an email to Marco")
        #expect(RewritePrompts.usableNote("x", content: "milk eggs", transcript: "milk eggs. Put that in bullet points.") == "Put that in bullet points")
    }

    @Test func noNoteWhenTheSplitDoesNotCheckOut() {
        let spoken = "what's the best time to call you tomorrow I'm free after lunch"
        #expect(RewritePrompts.usableNote(spoken, content: spoken, transcript: spoken) == nil)
        #expect(RewritePrompts.usableNote("call", content: "the best time", transcript: spoken) == nil)
        #expect(RewritePrompts.usableNote("x", content: "", transcript: spoken) == nil)
    }

    @Test func toneAddsARuleOnlyWhenPicked() {
        #expect(!RewritePrompts.instructions(for: .init(task: .polish, transcript: "x")).contains("Tone:"))
        let formal = RewriteRequest(task: .polish, transcript: "x", context: .init(tone: .formal))
        #expect(RewritePrompts.instructions(for: formal).contains("Tone: formal"))
    }

    @Test func dictionaryTermsPinSpelling() {
        let plain = RewritePrompts.instructions(for: .init(task: .polish, transcript: "x"))
        #expect(!plain.contains("Spell these"))
        let request = RewriteRequest(task: .polish, transcript: "x", context: .init(dictionaryTerms: ["Nanth", " ", "Okafor"]))
        #expect(RewritePrompts.instructions(for: request).hasSuffix("- Spell these names and terms exactly as given: Nanth, Okafor."))
        let edit = RewriteRequest(task: .edit(instruction: "shorter", selection: "y"), transcript: "shorter", context: .init(dictionaryTerms: ["Nanth"]))
        #expect(RewritePrompts.instructions(for: edit).contains("exactly as given: Nanth."))
    }
}
