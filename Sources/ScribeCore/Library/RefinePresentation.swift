import Foundation
import FoundationModels

public enum RefinePresentation {
    public static func status(gemmaInstalled: Bool) -> String {
        if gemmaInstalled { return "Gemma installed" }
        switch SystemLanguageModel.default.availability {
        case .available: return "Ready"
        case .unavailable(.deviceNotEligible): return "Not supported on this device"
        case .unavailable: return "Turn on Apple Intelligence"
        }
    }

    public static var preparationDetail: String? {
        if case .unavailable(.modelNotReady) = SystemLanguageModel.default.availability {
            return "Apple Intelligence is preparing its model."
        }
        return nil
    }

    @MainActor public static func translateLabel(text: String, outputLanguage: String, languages: [String]) -> String {
        let target = NoteEditor.translationTarget(text: text, outputLanguage: outputLanguage, languages: languages)
        let ui = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return "Translate → " + (ui.localizedString(forLanguageCode: target.language.languageCode?.identifier ?? target.identifier) ?? target.identifier)
    }
}
