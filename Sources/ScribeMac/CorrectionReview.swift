import ScribeCore
import SwiftUI

struct CorrectionReview: View {
    let learning: LearningModel
    let vocabulary: Vocabulary

    var body: some View {
        Section {
            if learning.document.corrections.entries.isEmpty {
                Text("Nothing yet. When you fix a word Scribe got wrong, it shows up here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(learning.document.corrections.newestFirst) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.pair.heard) → \(entry.pair.meant)")
                    Text(entry.caption).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Add") { learning.add(entry.pair, to: vocabulary) }
                            .accessibilityIdentifier("correction.add")
                        if entry.state == .ignored {
                            Button("Forget") { learning.forget(entry.pair) }.accessibilityIdentifier("correction.forget")
                        } else {
                            Button("Ignore") { learning.ignore(entry.pair) }.accessibilityIdentifier("correction.ignore")
                        }
                    }.buttonStyle(.borderless)
                }
            }
        } header: { Text("Corrections") }
        footer: { Text("Scribe noticed you fixing these.") }
    }
}

struct ContactsNamesSection: View {
    let contacts: ContactsNames

    var body: some View {
        Section {
            Toggle("Use names from Contacts", isOn: Binding(get: { contacts.enabled }, set: { contacts.setEnabled($0) }))
            if let failure = contacts.failure {
                // DESIGN: A failed local Contacts read uses a native secondary text row.
                Text(failure).foregroundStyle(.secondary)
            }
        } footer: { Text("Helps Scribe spell the people you know. Names never leave this device.") }
    }
}
