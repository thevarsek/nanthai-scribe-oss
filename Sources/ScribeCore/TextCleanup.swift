import Foundation

/// Light, deterministic tidy-up between transcription and insertion.
///
/// The speech model already punctuates and capitalizes; this only removes what it leaves
/// behind. Rewriting (the "Polish" brain-dump mode) is a separate, model-backed step.
public enum TextCleanup {
    private static let fillers = ["um", "uh", "erm", "uhm", "hmm", "mm"]

    public static func clean(_ raw: String, dictionary: [DictionaryEntry]) -> String {
        DictionaryReplacement.apply(to: clean(raw), dictionary: dictionary)
    }

    public static func clean(_ raw: String) -> String {
        var text = raw
        for filler in fillers {
            // Whole word, plus the comma the recognizer often attaches to it.
            text = text.replacingOccurrences(
                of: "(?i)(?<![\\w'])\(filler)\\b[,.]?",
                with: "",
                options: .regularExpression
            )
        }
        text = text
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "^[\\s,.]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Dropping a leading filler can leave the sentence starting lowercase.
        if let first = text.first, first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }
}
