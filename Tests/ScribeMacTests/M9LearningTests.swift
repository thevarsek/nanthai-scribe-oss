import AppKit
import ApplicationServices
import Foundation
import ScribeCore
import Testing
@testable import ScribeMac

@MainActor
@Suite struct M9MacLearningTests {
    @Test func valueOnlyAXFieldsResolveUniqueNewInsertions() {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let target = AXCorrectionWatch.Target(element: element, inserted: "Nantai", previousValue: "Ask  today", startedAt: .now)
        let span = target.resolved(in: "Ask Nantai today")
        #expect(span?.prefix == "Ask ")
        #expect(span?.suffix == " today")
        #expect(span?.current(in: "Ask NanthAi today", at: .now) == "NanthAi")
        #expect(target.resolved(in: "Ask  today") == nil)
        #expect(target.resolved(in: "Nantai and Nantai") == nil)
        #expect(target.resolved(in: "Missing insertion") == nil)
    }

    @Test func hudAddAndDeferralDoNotTakeFocus() throws {
        let suite = "M9Mac-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        let pair = CorrectionPair(heard: "Nantai", meant: "NanthAi")
        #expect(dictation.learning.record(pair, canAsk: true))
        dictation.previewCorrection(pair)
        _ = NSApplication.shared
        let panel = HUDController.makePanel(dictation: dictation)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.ignoresMouseEvents)
        dictation.dismissCorrection()
        #expect(dictation.correctionPrompt == nil)
        #expect(dictation.learning.document.corrections.entries[0].deferrals == 1)
        dictation.previewCorrection(pair)
        dictation.addCorrection()
        #expect(dictation.dictionary.first?.source == .learned)
        #expect(dictation.dictionary.first?.variants == ["Nantai"])
        #expect(dictation.correctionAdded)
        #expect(dictation.learning.document.corrections.entries.isEmpty)
        dictation.previewCorrection(nil)
    }
}
