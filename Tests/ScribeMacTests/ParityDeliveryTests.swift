import Foundation
import Observation
import Synchronization
import ScribeCore
import Testing
@testable import ScribeMac

@MainActor @Suite struct ParityDeliveryTests {
    @Test func failedVoiceEditDoesNotPasteAndRetainsItsInstruction() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PAR1-edit-\(UUID())")
        let name = "PAR1-edit-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        var pasted = false
        dictation.insertText = { _, _ in pasted = true }
        dictation.previewFailedVoiceEdit("Synthetic edit instruction")
        #expect(!pasted)
        #expect(dictation.phase == .failed("Couldn't edit. Your text is unchanged."))
        #expect(dictation.lastDictation?.text == "Synthetic edit instruction")
        dictation.previewFailedVoiceEdit("")
        #expect(!pasted)
        #expect(dictation.phase == .failed("Couldn't edit. Your text is unchanged."))
        #expect(dictation.lastDictation?.text == "Synthetic edit instruction")
        let changed = Mutex(false)
        withObservationTracking { _ = dictation.lastDictation } onChange: { changed.withLock { $0 = true } }
        _ = dictation.lastDictation
        #expect(!changed.withLock { $0 })
    }
}
