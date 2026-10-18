import ScribeCore
import SwiftUI

struct DictionarySettings: View {
    @Bindable var vocabulary: Vocabulary
    let learning: LearningModel
    let contacts: ContactsNames
    private var dictionary: [DictionaryEntry] {
        get { vocabulary.dictionary }
        nonmutating set { vocabulary.dictionary = newValue }
    }

    var body: some View {
        Section {
            if dictionary.isEmpty {
                Text("Add names, brands and terms Scribe gets wrong.")
                    .foregroundStyle(.secondary)
            }
            ForEach(dictionary) { entry in
                DictionaryRow(entry: Binding(
                    get: { dictionary.first { $0.id == entry.id } ?? entry },
                    set: { updated in
                        if let index = dictionary.firstIndex(where: { $0.id == entry.id }) { dictionary[index] = updated }
                    }
                )) { dictionary.removeAll { $0.id == entry.id } }
            }
            Button("Add word", systemImage: "plus") { dictionary.append(DictionaryEntry()) }
        } header: {
            Text("Dictionary")
        } footer: {
            Text("Scribe offers to add words you correct, and lists them under Corrections.")
        }
        ContactsNamesSection(contacts: contacts)
        CorrectionReview(learning: learning, vocabulary: vocabulary)
        // DESIGN: Local persistence errors use the existing native retry affordance.
        if let failure = learning.saveFailure {
            Text(failure.message).foregroundStyle(.secondary)
            Button("Retry", action: learning.reload)
        }
    }
}

private struct DictionaryRow: View {
    private enum Field: Hashable { case term, variants }
    @Binding var entry: DictionaryEntry
    let delete: () -> Void
    @State private var variants: String
    @FocusState private var focused: Field?

    init(entry: Binding<DictionaryEntry>, delete: @escaping () -> Void) {
        _entry = entry
        self.delete = delete
        // Keep a draft until Return or focus loss, so typing commas doesn't reset the field.
        _variants = State(initialValue: entry.wrappedValue.variants.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Hidden labels: in a grouped Form a labelled field right-aligns the word.
                TextField("Word or name", text: $entry.term, prompt: Text("Word or name"))
                    .labelsHidden()
                    .focused($focused, equals: .term)
                    .onSubmit(commitVariants)
                Button("Delete", systemImage: "minus.circle", role: .destructive, action: delete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            if entry.source == .learned { Text("Learned").font(.caption).foregroundStyle(.secondary) }
            TextField("Heard as", text: $variants, prompt: Text("Heard as (optional, comma-separated)"))
                .labelsHidden()
                .font(.callout)
                .foregroundStyle(.secondary)
                .focused($focused, equals: .variants)
                .onSubmit(commitVariants)
        }
        .background(SettingsWindowCloseHook(close: commitVariants))
        .onChange(of: focused) { previous, _ in if previous != nil { commitVariants() } }
        .onDisappear(perform: commitVariants)
    }

    private func commitVariants() {
        entry.variants = DictionaryEntry.parseVariants(variants, term: entry.term)
        variants = entry.variants.joined(separator: ", ")
    }
}
