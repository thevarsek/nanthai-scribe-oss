import Foundation
import NaturalLanguage

/// Chooses between transcripts of the same audio produced by different language models.
///
/// Recognizer confidence alone isn't enough: a model hearing a foreign language often
/// transcribes it phonetically *in that foreign language* with high confidence (the Italian
/// model scores ~0.93 on English speech, writing English words). So each candidate's
/// confidence is weighted by how strongly its text reads as the model's own language —
/// a model whose output is in another language has misheard.
public enum LanguagePicker {
    public struct Candidate: Sendable {
        public let locale: Locale
        public let text: String
        public let confidence: Double

        public init(locale: Locale, text: String, confidence: Double) {
            self.locale = locale
            self.text = text
            self.confidence = confidence
        }
    }

    public static func best(of candidates: [Candidate]) -> Candidate? {
        bestIndex(of: candidates).map { candidates[$0] }
    }

    /// Retains candidate identity when batch and Apple lanes happen to agree verbatim.
    static func bestIndex(of candidates: [Candidate]) -> Int? {
        let nonEmpty = candidates.indices.filter { !candidates[$0].text.isEmpty }
        guard nonEmpty.count > 1 else { return nonEmpty.first ?? candidates.indices.first }
        let languages = Set(nonEmpty.compactMap { language(for: candidates[$0].locale) })
        return nonEmpty.max { score(candidates[$0], among: languages) < score(candidates[$1], among: languages) }
    }

    static func score(_ candidate: Candidate, among languages: Set<NLLanguage>) -> Double {
        // When the text-language check can't help (one shared language such as en_GB vs
        // en_US, or a language NaturalLanguage doesn't know), confidence decides alone.
        guard languages.count > 1, let own = language(for: candidate.locale) else {
            return candidate.confidence
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Array(languages)
        recognizer.processString(candidate.text)
        let match = recognizer.languageHypotheses(withMaximum: languages.count)[own] ?? 0
        // Floor the weight so very short utterances ("ok", "sì"), where text-language
        // detection is a coin flip, still lean on confidence.
        return candidate.confidence * (0.2 + 0.8 * match)
    }

    /// The written language a speech locale produces, as NaturalLanguage names it.
    static func language(for locale: Locale) -> NLLanguage? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        switch code {
        case "zh":
            let region = locale.region?.identifier
            return region == "TW" || region == "HK" ? .traditionalChinese : .simplifiedChinese
        case "yue":
            return nil // Cantonese has no NaturalLanguage model; fall back to confidence.
        default:
            let language = NLLanguage(rawValue: code)
            return language == .undetermined ? nil : language
        }
    }
}
