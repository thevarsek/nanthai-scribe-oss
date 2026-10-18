import Foundation
import NaturalLanguage

/// Pure routing and labelling shared by the live pipeline and language settings.
public enum BatchRouting {
    public static func languageCode(_ locale: Locale) -> String {
        locale.language.languageCode?.identifier ?? locale.identifier
    }

    public static func matching(_ chosen: [Locale], supportedBy engine: [Locale]) -> [Locale] {
        let codes = Set(engine.map(languageCode))
        return chosen.filter { codes.contains(languageCode($0)) }
    }

    public static func batchOnly(_ supported: [Locale], appleLocales: [Locale]) -> [Locale] {
        let apple = Set(appleLocales.map(languageCode))
        return supported.filter { !apple.contains(languageCode($0)) }
    }

    /// Parakeet does not emit a language ID. Preserve the user's regional locale when
    /// labelling its text, and never introduce a language outside the selected set.
    public static func detectedLocale(for text: String, among chosen: [Locale]) -> Locale? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let pairs = chosen.compactMap { locale in LanguagePicker.language(for: locale).map { (locale, $0) } }
        guard !pairs.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Array(Set(pairs.map(\.1)))
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return pairs.first?.0 }
        return pairs.first { $0.1 == language }?.0
    }
}
