import ScribeCore
import SwiftUI

struct SnippetsSettings: View {
    @Binding var snippets: [Snippet]

    var body: some View {
        // DESIGN: Mac snippets use native inline fields and immediate add/delete in the Settings Form.
        Section {
            // DESIGN: A native text example introduces snippets when the collection is empty.
            if snippets.isEmpty { Text("Say “my signature” → insert “Best wishes, Sam”.").foregroundStyle(.secondary) }
            ForEach($snippets) { $snippet in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Trigger phrase", text: $snippet.trigger)
                        Button("Delete", systemImage: "minus.circle", role: .destructive) {
                            snippets.removeAll { $0.id == snippet.id }
                        }.labelStyle(.iconOnly)
                    }
                    TextField("Text", text: $snippet.text, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            Button("Add snippet", systemImage: "plus") { snippets.append(Snippet()) }
        } header: { Text("Snippets") }
        footer: { Text("Say a trigger phrase to insert its text. Triggers match whole words. Say only the trigger to insert the text verbatim, even with Refine on.") }
    }
}
