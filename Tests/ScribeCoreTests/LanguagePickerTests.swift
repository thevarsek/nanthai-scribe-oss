import Foundation
import Testing
@testable import ScribeCore

/// Confidences are the real values measured on TTS clips through it_IT and en_GB models.
@Suite struct LanguagePickerTests {
    let it = Locale(identifier: "it_IT")
    let en = Locale(identifier: "en_GB")

    @Test func englishSpeechPicksEnglishEvenWhenItalianIsConfident() {
        let best = LanguagePicker.best(of: [
            .init(locale: it, text: "So we just finished working on the ph to stuff and now I want to test the transcription quality", confidence: 0.952),
            .init(locale: en, text: "So we just finished working on the phase 2 stuff, and now I want to test the transcription quality.", confidence: 0.965),
        ])
        #expect(best?.locale == en)
    }

    @Test func italianSpeechPicksItalian() {
        let best = LanguagePicker.best(of: [
            .init(locale: it, text: "Ciao Marco, possiamo spostare il lancio a mercoledì il design non è ancora pronto", confidence: 0.962),
            .init(locale: en, text: "Ciao, Marco, pociamos postari lancho amercoledi, il design non encora prunto", confidence: 0.430),
        ])
        #expect(best?.locale == it)
    }

    @Test func textLanguageOverridesHigherConfidence() {
        // The wrong model is *more* confident, but its output isn't in its own language.
        let best = LanguagePicker.best(of: [
            .init(locale: it, text: "Can we move the launch to Wednesday because the design isn't ready", confidence: 0.97),
            .init(locale: en, text: "Can we move the launch to Wednesday because the design isn't ready", confidence: 0.90),
        ])
        #expect(best?.locale == en)
    }

    @Test func worksBeyondItalianAndEnglish() {
        let de = Locale(identifier: "de_DE"), fr = Locale(identifier: "fr_FR")
        let best = LanguagePicker.best(of: [
            .init(locale: de, text: "Können wir den Start auf Mittwoch verschieben, das Design ist noch nicht fertig", confidence: 0.94),
            .init(locale: fr, text: "Kœnig vire den starte auf mitre fois chez bain das désigne ist noch nicht fertig", confidence: 0.91),
        ])
        #expect(best?.locale == de)
    }

    @Test func chineseScriptsMapByRegion() {
        #expect(LanguagePicker.language(for: Locale(identifier: "zh_CN")) == .simplifiedChinese)
        #expect(LanguagePicker.language(for: Locale(identifier: "zh_TW")) == .traditionalChinese)
        #expect(LanguagePicker.language(for: Locale(identifier: "yue_CN")) == nil)
    }

    @Test func singleCandidatePassesThrough() {
        #expect(LanguagePicker.best(of: [.init(locale: en, text: "Hi", confidence: 0.5)])?.locale == en)
    }
}

extension LanguagePickerTests {
    @Test func portugueseOverCloseSpanish() {
        let es = Locale(identifier: "es_ES"), pt = Locale(identifier: "pt_BR")
        let best = LanguagePicker.best(of: [
            .init(locale: es, text: "Podemos alear o lanzamamiento para cuarta feira o desi nainda não está pronto.", confidence: 0.751),
            .init(locale: pt, text: "Podemos adiar o lançamento para quarta-feira? O design ainda não está pronto.", confidence: 0.969),
        ])
        #expect(best?.locale == pt)
    }
}
