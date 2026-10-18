import Foundation
import Observation
import Sparkle

/// Created by the app delegate, never by render fixtures. Sparkle's persisted preference
/// starts false in Info.plist; starting the updater does not perform a manual check.
@MainActor
@Observable
final class Updates {
    private let controller: SPUStandardUpdaterController
    private var started = false
    var automaticallyChecks: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            if automaticallyChecks { start() }
        }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        if automaticallyChecks { start() }
    }

    func checkForUpdates() {
        start()
        controller.checkForUpdates(nil)
    }

    private func start() {
        guard !started else { return }
        started = true
        controller.startUpdater()
    }
}
