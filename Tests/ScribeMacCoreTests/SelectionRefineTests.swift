import ScribeCore
import Testing
@testable import ScribeMacCore

@Suite struct SelectionRefineTests {
    @Test func silenceWithSelectionUsesDefaultPolish() {
        let request = SelectionRefine.request(speech: "", selection: "Could you explain this?", polish: true)
        #expect(request?.task == .polish)
        #expect(request?.transcript == "Could you explain this?")
        #expect(request?.context.outputLanguage == nil)
    }

    @Test func ordinaryDictationAndSpokenEditsKeepExistingRoutes() {
        #expect(SelectionRefine.request(speech: "Make it shorter", selection: "Selected text", polish: true) == nil)
        #expect(SelectionRefine.request(speech: "", selection: nil, polish: true) == nil)
        #expect(SelectionRefine.request(speech: "", selection: "", polish: true) == nil)
        #expect(SelectionRefine.request(speech: "", selection: "Selected text", polish: false) == nil)
    }
}
