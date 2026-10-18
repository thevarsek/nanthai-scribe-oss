import AppKit
import ScribeCore
import SwiftUI
import UniformTypeIdentifiers

struct AppStyleSection: View {
    let settings: AppStyleSettings
    let defaultTone: RewriteTone
    /// Render fixtures can supply a small installed-app list without changing preferences.
    var applications: [AppStyleApplication]?
    @State private var installed: [AppStyleApplication] = []
    @State private var selection: String?

    private var rows: [AppStyleApplication] { applications ?? installed }

    var body: some View {
        Section {
            ForEach(rows) { app in
                HStack {
                    // DESIGN: A plain native button selects the row for the minus button.
                    Button { selection = app.id } label: {
                        HStack {
                            Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                            Text(app.name).font(.system(size: 13))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == app.id ? .isSelected : [])
                    Picker(app.name, selection: Binding(
                        get: { settings.choice(for: app.id) },
                        set: { settings.set($0, for: app.id); selection = app.id }
                    )) {
                        Text("Default (\(defaultTone.rawValue.capitalized))").tag("default")
                        ForEach(RewriteTone.allCases, id: \.rawValue) { tone in
                            Text(tone.rawValue.capitalized).tag(tone.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                // DESIGN: Native selection background makes the minus button's target visible.
                .background(selection == app.id ? Rectangle().fill(.selection) : nil)
            }
            HStack {
                Button("Add app", systemImage: "plus", action: add).labelStyle(.iconOnly)
                Button("Remove or reset app", systemImage: "minus") {
                    guard let selection else { return }
                    settings.reset(selection)
                    self.selection = nil
                    refresh()
                }
                .labelStyle(.iconOnly).disabled(selection == nil)
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Style by app")
        } footer: {
            Text("Scribe picks a tone for the app you're dictating into. Saying “more formal” still wins.")
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        guard applications == nil else { return }
        installed = AppStyleApplication.installed(addedIDs: Array(settings.choices.keys))
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let app = AppStyleApplication(url: url) else { return }
            if settings.choices[app.id] == nil { settings.set(settings.choice(for: app.id), for: app.id) }
            refresh()
            selection = app.id
        }
    }
}
