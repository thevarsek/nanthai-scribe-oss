import AppKit
import Foundation
import Testing
@testable import ScribeMac

@MainActor @Suite(.serialized) struct HUDLifetimeTests {
    @Test func observationDoesNotRetainTheDictationAfterControllerRelease() async throws {
        _ = NSApplication.shared
        let name = "HUDLifetime-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let root = FileManager.default.temporaryDirectory.appending(path: name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        weak var releasedModel: Dictation?
        weak var releasedController: HUDController?
        do {
            let model = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"),
                                  vocabularyDirectory: root)
            let controller = HUDController(dictation: model)
            releasedModel = model
            releasedController = controller
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(releasedController == nil)
        #expect(releasedModel == nil)
    }
}
