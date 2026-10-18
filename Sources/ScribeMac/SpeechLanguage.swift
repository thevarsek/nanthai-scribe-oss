import Foundation

/// Display names for speech locales, in the app's UI language (English until localized),
/// so names don't switch language mid-sentence with the surrounding copy.
enum SpeechLanguage {
    private static let ui = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

    static func languageName(_ locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? locale.identifier
        return ui.localizedString(forLanguageCode: code) ?? code
    }

    /// "English (United Kingdom)"
    static func name(_ locale: Locale) -> String {
        ui.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// "EN-GB" — compact, for the menu title.
    static func shortName(_ locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier.uppercased() ?? locale.identifier
        guard let region = locale.region?.identifier else { return code }
        return "\(code)-\(region)"
    }
}
