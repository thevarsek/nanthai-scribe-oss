import Foundation
import OSLog
import Speech

/// Keeps readiness checks and reservation recovery testable without contacting Apple's asset service.
@MainActor
protocol SpeechAssetInventory {
    var status: AssetInventory.Status { get async }
    var installedLocales: [Locale] { get async }
    var reservedLocales: [Locale] { get async }
    var maximumReservedLocales: Int { get }
    func install(progress: (@MainActor (Double?) -> Void)?) async throws
    func release(_ locale: Locale) async -> Bool
}

enum SpeechAssetPreparationError: LocalizedError {
    case notInstalled(Locale)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let locale):
            "Speech assets for \(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier) couldn't be prepared. Try again in Settings › Languages."
        }
    }
}

@MainActor
enum SpeechAssetPreparation {
    private static let logger = Logger(subsystem: "tech.nanthai.Scribe", category: "SpeechAssets")

    static func prepare(module: SpeechTranscriber, locale: Locale, enabledLocales: [Locale]?,
                        progress: (@MainActor (Double?) -> Void)? = nil) async throws {
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        try await prepare(inventory: AppleSpeechAssetInventory(module: module, locale: supported), locale: supported,
                          enabledLocales: enabledLocales, progress: progress)
    }

    /// A nil enabled-language list means the caller cannot identify stale reservations safely.
    static func prepare(inventory: any SpeechAssetInventory, locale: Locale, enabledLocales: [Locale]?,
                        progress: (@MainActor (Double?) -> Void)? = nil) async throws {
        try Task.checkCancellation()
        let before = await inventory.status
        if before == .installed {
            _ = isReady(locale: locale, statusBefore: before, statusAfter: before,
                        installedLocales: await inventory.installedLocales)
            return
        }
        logger.info("locale=\(locale.identifier, privacy: .public) statusBefore=\(String(describing: before), privacy: .public) decision=requestInstallation")
        do {
            try await inventory.install(progress: progress)
        } catch {
            try Task.checkCancellation()
            guard let speechError = error as? SFSpeechError,
                  speechError.code == .tooManyAssetLocalesAllocated,
                  let enabledLocales else { throw error }
            let reserved = await inventory.reservedLocales
            // Apple may return regional variants. Preserve every variant of an enabled language,
            // as well as the requested module's language (including recovered recordings).
            let protected = Set((enabledLocales + [locale]).map(languageIdentifier))
            guard reserved.count >= inventory.maximumReservedLocales,
                  let stale = reserved.first(where: { !protected.contains(languageIdentifier($0)) }) else { throw error }
            // A false result means another request already released it; retry in either case.
            _ = await inventory.release(stale)
            try await inventory.install(progress: progress)
        }
        try Task.checkCancellation()
        let after = await inventory.status
        guard isReady(locale: locale, statusBefore: before, statusAfter: after,
                      installedLocales: await inventory.installedLocales) else {
            throw SpeechAssetPreparationError.notInstalled(locale)
        }
    }

    /// Callers resolve the module locale with SpeechTranscriber first. Compare canonical tags
    /// so separator differences match without treating distinct supported regions as equivalent.
    static func isReady(locale: Locale, statusBefore: AssetInventory.Status, statusAfter: AssetInventory.Status,
                        installedLocales: [Locale]) -> Bool {
        let installed = installedLocales.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        // The per-app Speech XPC service can leave status stale after exiting while idle.
        let ready = statusAfter == .installed || installed
        logger.info("locale=\(locale.identifier, privacy: .public) statusBefore=\(String(describing: statusBefore), privacy: .public) statusAfter=\(String(describing: statusAfter), privacy: .public) installedLocale=\(installed, privacy: .public) decision=\(ready ? "proceed" : "notInstalled", privacy: .public)")
        return ready
    }

    private static func languageIdentifier(_ locale: Locale) -> String {
        locale.language.languageCode?.identifier ?? locale.identifier
    }
}

@MainActor
private struct AppleSpeechAssetInventory: SpeechAssetInventory {
    let module: SpeechTranscriber
    let locale: Locale
    private static let logger = Logger(subsystem: "tech.nanthai.Scribe", category: "SpeechAssets")
    var status: AssetInventory.Status { get async { await AssetInventory.status(forModules: [module]) } }
    var installedLocales: [Locale] { get async { await SpeechTranscriber.installedLocales } }
    var reservedLocales: [Locale] { get async { await AssetInventory.reservedLocales } }
    var maximumReservedLocales: Int { AssetInventory.maximumReservedLocales }

    func release(_ locale: Locale) async -> Bool { await AssetInventory.release(reservedLocale: locale) }

    func install(progress: (@MainActor (Double?) -> Void)?) async throws {
        // Disk availability is system-wide; this request also reserves the exact module
        // configuration for this app, even when no bytes need downloading.
        let request = try await AssetInventory.assetInstallationRequest(supporting: [module])
        Self.logger.info("locale=\(locale.identifier, privacy: .public) installationRequest=\(request == nil ? "nil" : "non-nil", privacy: .public)")
        guard let request else { return }
        progress?(0)
        let observer = Task {
            while !Task.isCancelled {
                progress?(request.progress.fractionCompleted)
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
        defer { observer.cancel(); progress?(nil) }
        try await request.downloadAndInstall()
    }
}
