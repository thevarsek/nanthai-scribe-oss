import FluidAudio
import Foundation

/// Parakeet TDT v3 runs exclusively from the verified ModelStore snapshot.
public actor ParakeetTranscriber: BatchTranscriber {
    public nonisolated let id = "parakeet-v3"
    public nonisolated let sampleRate: Double = 16_000
    public nonisolated let languages = ParakeetTranscriber.supportedLanguages
    public nonisolated static let supportedLanguages: [Locale] = [
        "bg_BG", "hr_HR", "cs_CZ", "da_DK", "nl_NL", "en_GB", "et_EE", "fi_FI", "fr_FR",
        "de_DE", "el_GR", "hu_HU", "it_IT", "lv_LV", "lt_LT", "mt_MT", "pl_PL", "pt_PT",
        "ro_RO", "ru_RU", "sk_SK", "sl_SI", "es_ES", "sv_SE", "uk_UA",
    ].map { Locale(identifier: $0) }

    public static var appleUnsupportedLanguages: [Locale] {
        get async { BatchRouting.batchOnly(supportedLanguages, appleLocales: await LiveTranscriber.supportedLocales) }
    }

    private let modelDirectory: URL
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    public init(modelDirectory: URL) { self.modelDirectory = modelDirectory }

    public func isAvailable() async -> Bool {
        guard ModelStore.isInstalled(ModelCatalog.parakeet, at: modelDirectory) else { return false }
        do { _ = try await load(); return true } catch { return false }
    }

    public func transcribe(samples: [Float], sampleRate: Double) async throws -> BatchTranscript {
        guard sampleRate == self.sampleRate else { throw ScribeError.noAudioFormat }
        guard !samples.isEmpty else { return BatchTranscript(text: "") }
        guard ModelStore.isInstalled(ModelCatalog.parakeet, at: modelDirectory) else {
            throw RewriteError.unavailable("Download the Parakeet language pack first.")
        }
        let manager = try await load()
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &state)
        return BatchTranscript(text: result.text, confidence: Double(result.confidence))
    }

    /// Word timings from the whole file, in file seconds; FluidAudio chunks long audio itself.
    public func transcribe(file url: URL) async throws -> [MeetingWord] {
        guard ModelStore.isInstalled(ModelCatalog.parakeet, at: modelDirectory) else {
            throw RewriteError.unavailable("Download the Parakeet language pack first.")
        }
        let manager = try await load()
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(url, decoderState: &state)
        let words = buildWordTimings(from: result.tokenTimings ?? [])
        guard !words.isEmpty else {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [MeetingWord(text: text, start: 0, end: result.duration)]
        }
        return words.map { MeetingWord(text: $0.word, start: $0.startTime, end: $0.endTime) }
    }

    /// The opening stretch of a file as a language candidate, labelled only with a pack language.
    public func probe(file url: URL, among locales: [Locale], seconds: Double) async throws -> LanguagePicker.Candidate? {
        let samples = Array(try AudioConverter().resampleAudioFile(url).prefix(Int(seconds * sampleRate)))
        let result = try await transcribe(samples: samples, sampleRate: sampleRate)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locale = BatchRouting.detectedLocale(for: text, among: BatchRouting.matching(locales, supportedBy: languages)) else {
            return nil
        }
        return .init(locale: locale, text: text, confidence: result.confidence ?? 0.5)
    }

    public func unload() { manager = nil }

    private func load() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let directory = modelDirectory
        let task = Task.detached(priority: .userInitiated) {
            let models = try AsrModels.loadLocal(from: directory, version: .v3)
            let manager = AsrManager()
            try await manager.loadModels(models)
            return manager
        }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value
        manager = loaded
        return loaded
    }
}
