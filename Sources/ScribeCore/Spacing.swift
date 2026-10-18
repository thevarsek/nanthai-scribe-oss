import Foundation

/// Joins a dictation onto whatever already sits before the cursor, so consecutive
/// punch-ins don't run together ("Hello.How are you").
public enum Spacing {
    /// - Parameter before: the character immediately before the insertion point, or nil
    ///   at the start of a field.
    public static func needsLeadingSpace(before: Character?, inserting text: String) -> Bool {
        guard let before, let first = text.first else { return false }
        if before.isWhitespace || first.isWhitespace { return false }
        // No space after an opening bracket/quote, or before closing punctuation.
        if "([{\"'“‘/-".contains(before) { return false }
        if ".,;:!?)]}”’".contains(first) { return false }
        return true
    }
}
