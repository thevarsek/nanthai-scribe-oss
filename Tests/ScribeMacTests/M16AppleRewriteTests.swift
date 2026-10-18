import Foundation
import ScribeCore
import Testing

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M16_APPLE_VERIFY"] == "1"))
struct M16AppleRewriteTests {
    @Test func editorPresetsRunThroughAppleInEnglishItalianAndGerman() async throws {
        let engine = AppleRewriter()
        #expect(await engine.isAvailable())
        let fixtures = [
            ("en", "we has a meeting tomorow at ten please bring the project notes"),
            ("it", "domani noi ha una riunione alle dieci porta i appunti del progetto per favore"),
            ("de", "morgen haben wir ein treffen um zehn bitte bring die projektnotizen mit")]
        var report = ["Apple rewriter: editor end-to-end preset verification"]
        for (language, text) in fixtures {
            let editor = NoteEditor(note: Note(text: text))
            let started = ContinuousClock.now
            await editor.apply(.proofread, rewriter: engine, languages: [language])
            #expect(editor.failure == nil)
            #expect(!editor.text.isEmpty)
            #expect(editor.text != text, "The deliberately ungrammatical fixture should be corrected.")
            #expect(!editor.isRunning)
            report.append("\(language): success=\(editor.failure == nil), inputLength=\(text.count), resultLength=\(editor.text.count), duration=\(started.duration(to: .now))")
        }
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_M16_RENDER_DIR"] {
            try report.joined(separator: "\n").write(to: URL(filePath: directory).appending(path: "apple-rewrite.txt"), atomically: true, encoding: .utf8)
        }
    }
}
