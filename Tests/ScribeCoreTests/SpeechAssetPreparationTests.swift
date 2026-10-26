import Foundation
import Speech
import Testing
@testable import ScribeCore

@MainActor
struct SpeechAssetPreparationTests {
    private let italian = Locale(identifier: "it_IT")
    private let english = Locale(identifier: "en_GB")
    private let stale = Locale(identifier: "fr_FR")

    @Test func installedAssetsNeedNoRequest() async throws {
        let inventory = Inventory(status: .installed)
        try await prepare(inventory)
        #expect(inventory.installCount == 0)
        #expect(inventory.released.isEmpty)
    }

    @Test(arguments: ["supported", "downloading"])
    func preparesAssetsAlreadyOnDiskOrDownloading(status: String) async throws {
        let inventory = Inventory(status: status == "supported" ? .supported : .downloading)
        try await prepare(inventory)
        #expect(inventory.installCount == 1)
        #expect(inventory.status == .installed)
    }

    @Test(arguments: [true, false])
    func staleSupportedStatusAcceptsInstalledLocale(hasRequest: Bool) async throws {
        let inventory = Inventory(status: .supported)
        inventory.installedLocales = [italian]
        inventory.installsAssets = false
        inventory.hasRequest = hasRequest
        try await prepare(inventory)
        #expect(inventory.installCount == 1)
        #expect(inventory.status == .supported)
    }

    @Test func installedLocaleAppearingDuringInstallAcceptsStaleStatus() async throws {
        let inventory = Inventory(status: .supported)
        inventory.updatesStatus = false
        try await prepare(inventory)
        #expect(inventory.installCount == 1)
        #expect(inventory.status == .supported)
        #expect(inventory.installedLocales == [italian])
    }

    @Test func installedLocaleMatchesEquivalentIdentifier() async throws {
        let inventory = Inventory(status: .supported)
        inventory.installedLocales = [Locale(identifier: "it-IT")]
        inventory.installsAssets = false
        try await prepare(inventory)
        #expect(inventory.installCount == 1)
    }

    @Test func differentInstalledRegionDoesNotValidateRequestedLocale() async {
        let inventory = Inventory(status: .supported)
        inventory.installedLocales = [Locale(identifier: "en_US")]
        inventory.installsAssets = false
        await #expect(throws: SpeechAssetPreparationError.self) {
            try await SpeechAssetPreparation.prepare(inventory: inventory, locale: english, enabledLocales: [english])
        }
        #expect(inventory.installCount == 1)
    }

    @Test(arguments: [true, false])
    func nilRequestOrIncompleteInstallationMustNotPassValidation(hasRequest: Bool) async {
        let inventory = Inventory(status: .supported)
        inventory.installsAssets = false
        inventory.hasRequest = hasRequest
        await #expect(throws: SpeechAssetPreparationError.self) { try await prepare(inventory) }
        #expect(inventory.installCount == 1)
    }

    @Test func readinessUsesInstalledLocalesWhenStatusIsStale() {
        #expect(SpeechAssetPreparation.isReady(locale: english, statusBefore: .supported, statusAfter: .supported,
                                             installedLocales: [english]))
        #expect(!SpeechAssetPreparation.isReady(locale: italian, statusBefore: .supported, statusAfter: .supported,
                                              installedLocales: [english]))
        #expect(SpeechAssetPreparation.isReady(locale: italian, statusBefore: .supported, statusAfter: .installed,
                                             installedLocales: []))
    }

    @Test func retriesOnceAfterReleasingOnlyDisabledLanguage() async throws {
        let inventory = Inventory(status: .supported, reserved: [english, stale])
        inventory.failures = [limitError]
        try await prepare(inventory)
        #expect(inventory.installCount == 2)
        #expect(inventory.released == [stale])
    }

    @Test func preservesRegionalVariantsOfEnabledLanguages() async {
        let inventory = Inventory(status: .supported, reserved: [Locale(identifier: "en_US"), italian])
        inventory.failures = [limitError]
        await #expect(throws: SFSpeechError.self) { try await prepare(inventory) }
        #expect(inventory.installCount == 1)
        #expect(inventory.released.isEmpty)
    }

    @Test func preservesRequestedLocaleEvenWhenItIsFromAnOlderRecording() async {
        let inventory = Inventory(status: .supported, reserved: [english, italian])
        inventory.failures = [limitError]
        await #expect(throws: SFSpeechError.self) {
            try await SpeechAssetPreparation.prepare(inventory: inventory, locale: italian, enabledLocales: [english])
        }
        #expect(inventory.released.isEmpty)
    }

    @Test func unknownEnabledLanguagesNeverReleaseReservations() async {
        let inventory = Inventory(status: .supported, reserved: [english, stale])
        inventory.failures = [limitError]
        await #expect(throws: SFSpeechError.self) {
            try await SpeechAssetPreparation.prepare(inventory: inventory, locale: italian, enabledLocales: nil)
        }
        #expect(inventory.released.isEmpty)
    }

    @Test func unrelatedErrorsDoNotEvictLanguagesOrRetry() async {
        let inventory = Inventory(status: .supported, reserved: [english, stale])
        inventory.failures = [SFSpeechError(.noModel)]
        await #expect(throws: SFSpeechError.self) { try await prepare(inventory) }
        #expect(inventory.installCount == 1)
        #expect(inventory.released.isEmpty)
    }

    @Test func retryFailureDoesNotEvictAnotherLanguage() async {
        let inventory = Inventory(status: .supported, reserved: [stale, Locale(identifier: "de_DE")])
        inventory.failures = [limitError, limitError]
        await #expect(throws: SFSpeechError.self) { try await prepare(inventory) }
        #expect(inventory.installCount == 2)
        #expect(inventory.released == [stale])
    }

    @Test func localeReleasedByAnotherRequestStillRetriesOnce() async throws {
        let inventory = Inventory(status: .supported, reserved: [english, stale])
        inventory.failures = [limitError]
        inventory.releaseResult = false
        try await prepare(inventory)
        #expect(inventory.installCount == 2)
        #expect(inventory.released == [stale])
    }

    @Test func forwardsProgress() async throws {
        let inventory = Inventory(status: .supported)
        var progress: [Double?] = []
        try await SpeechAssetPreparation.prepare(inventory: inventory, locale: italian,
                                                 enabledLocales: [italian, english]) { progress.append($0) }
        #expect(progress == [0, 1, nil])
    }

    @Test func cancellationDoesNotReleaseOrRetry() async {
        let inventory = Inventory(status: .supported, reserved: [english, stale])
        inventory.failures = [CancellationError()]
        await #expect(throws: CancellationError.self) { try await prepare(inventory) }
        #expect(inventory.installCount == 1)
        #expect(inventory.released.isEmpty)
    }

    private var limitError: SFSpeechError { SFSpeechError(.tooManyAssetLocalesAllocated) }

    private func prepare(_ inventory: Inventory) async throws {
        try await SpeechAssetPreparation.prepare(inventory: inventory, locale: italian,
                                                 enabledLocales: [italian, english])
    }
}

@MainActor
private final class Inventory: SpeechAssetInventory {
    var status: AssetInventory.Status
    var installedLocales: [Locale] = []
    var reservedLocales: [Locale]
    let maximumReservedLocales = 2
    var failures: [any Error] = []
    var installsAssets = true
    var updatesStatus = true
    var hasRequest = true
    var releaseResult = true
    var installCount = 0
    var released: [Locale] = []

    init(status: AssetInventory.Status, reserved: [Locale] = []) {
        self.status = status; reservedLocales = reserved
    }

    func install(progress: (@MainActor (Double?) -> Void)?) async throws {
        installCount += 1
        if !failures.isEmpty { throw failures.removeFirst() }
        guard hasRequest else { return }
        progress?(0)
        if installsAssets {
            installedLocales = [Locale(identifier: "it_IT")]
            if updatesStatus { status = .installed }
        }
        progress?(1)
        progress?(nil)
    }

    func release(_ locale: Locale) async -> Bool {
        released.append(locale)
        reservedLocales.removeAll { $0 == locale }
        return releaseResult
    }
}
