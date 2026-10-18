import Foundation
import ScribeCore

/// Silence with a selection means Refine the selected writing, never an empty edit instruction.
public enum SelectionRefine {
    public static func request(speech: String, selection: String?, polish: Bool) -> RewriteRequest? {
        guard polish, speech.isEmpty, let selection, !selection.isEmpty else { return nil }
        return RewriteRequest(task: .polish, transcript: selection)
    }
}
