import AppKit
import ScribeCore
import ScribeMacCore
import ScribeUI
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    var error: String?

    var isEnabled: Bool { status == .enabled }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case languages, dictionary, snippets, polish, meetings, privacy, general, about

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .languages: "Languages"
        case .dictionary: "Dictionary"
        case .polish: "Refine"
        case .snippets: "Snippets"
        case .meetings: "Meetings"
        case .privacy: "History & Privacy"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .languages: "globe"
        case .dictionary: "character.book.closed"
        case .polish: ""
        case .snippets: "text.badge.plus"
        case .meetings: "record.circle"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    let dictation: Dictation
    let showOnboarding: () -> Void
    var recorder: MeetingRecorder?
    var updates: Updates?
    @State private var loginItem = LoginItem()
    @State private var selection: SettingsTab = .general
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selection) {
            ForEach(SettingsTab.allCases) { tab in
                Tab(value: tab) {
                    SettingsPane(tab: tab, dictation: dictation, loginItem: loginItem,
                                 showOnboarding: showOnboarding, recorder: recorder, updates: updates)
                } label: {
                    // Tab bars only render symbol images, so Refine uses the SF Symbol directly.
                    Label(tab.title, systemImage: tab == .polish ? "pencil.and.scribble" : tab.symbol)
                }
            }
        }
        .modifier(SaveFailureNotice(failure: dictation.vocabulary.saveFailure, retry: dictation.vocabulary.retrySave))
        .tint(Brand.coral)
        // DESIGN: Settings height is unspecified; use a fixed native pane with scrolling Forms.
        .frame(width: 600, height: 500)
        .background(SettingsWindowCloseHook {
            dictation.dictionary.removeAll { $0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        })
        .onAppear { loginItem.refresh(); dictation.learning.reload(); dictation.contacts.refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { loginItem.refresh() } }
    }
}

/// Settings can stay alive when its window closes, so disappearance isn't a close signal.
struct SettingsWindowCloseHook: NSViewRepresentable {
    let close: () -> Void

    func makeNSView(context: Context) -> CloseObserver {
        let view = CloseObserver()
        view.close = close
        return view
    }

    func updateNSView(_ view: CloseObserver, context: Context) { view.close = close }

    final class CloseObserver: NSView {
        var close: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                    name: NSWindow.willCloseNotification, object: window)
            }
        }

        @objc private func windowWillClose(_ notification: Notification) { close?() }
    }
}

/// Separate panes let the render harness inspect every tab without starting app services.
struct SettingsPane: View {
    let tab: SettingsTab
    @Bindable var dictation: Dictation
    @Bindable var loginItem: LoginItem
    var showOnboarding: () -> Void = {}
    var recorder: MeetingRecorder?
    var updates: Updates?
    var bundle: Bundle = .main
    var styleApplications: [AppStyleApplication]?
    @Environment(\.scenePhase) private var scenePhase
    @State private var appleStatus = RefinePresentation.status(gemmaInstalled: false)
    @State private var confirmClear = false
    @State private var confirmDeleteAll = false
    @AppStorage("meetingShowReminder") private var meetingReminder = true
    @AppStorage("meetingKeepAudio") private var meetingAudio = false

    var body: some View {
        Form {
            switch tab {
            case .general: general
            case .languages: languages
            case .dictionary: DictionarySettings(vocabulary: dictation.vocabulary, learning: dictation.learning, contacts: dictation.contacts)
            case .polish: polish
            case .snippets: SnippetsSettings(snippets: $dictation.snippets)
            case .meetings: meetings
            case .privacy: privacy
            case .about: about
            }
        }
        .formStyle(.grouped)
        .tint(Brand.coral)
        .onChange(of: scenePhase) { if scenePhase == .active { appleStatus = RefinePresentation.status(gemmaInstalled: false) } }
    }

    @ViewBuilder private var general: some View {
        Section {
            TalkShortcutRow(dictation: dictation)
        } footer: {
            Text("Foot pedals and stream-deck buttons work too: set them to send F13–F20, then press the button here.")
        }
        Section {
            LabeledContent(dictation.talkShortcut.title, value: "dictate")
            LabeledContent("+ Shift", value: "hands-free")
            LabeledContent("+ ⌘", value: "Refine")
            LabeledContent("Select text, then + ⌘", value: "edit selection")
        }
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updates?.automaticallyChecks ?? false },
                set: { updates?.automaticallyChecks = $0 }
            ))
        } footer: {
            Text("Asks scribe.nanthai.tech once a day. Sends nothing else.")
        }
        Section {
            Toggle("Sounds", isOn: $dictation.soundsEnabled)
            Toggle("Open at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
            if loginItem.status == .requiresApproval {
                // DESIGN: Use a native button for the system's login-item approval settings.
                Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            // DESIGN: Login registration failures use plain system error text; no extra action is required.
            if let error = loginItem.error { Text(error).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var languages: some View {
        Section {
            // DESIGN: List height is unspecified; native scrolling keeps More languages visible.
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(dictation.availableLanguages, id: \.identifier) { locale in
                        Toggle(SpeechLanguage.name(locale), isOn: Binding(
                            get: { dictation.isSelected(locale) },
                            set: { _ in dictation.toggle(locale) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
        } header: {
            Text("Dictation languages")
        } footer: {
            Text("Pick up to 3. Scribe detects which one you're speaking.")
        }
        // DESIGN: Apple asset preparation and retry use native controls below Languages.
        if let progress = dictation.assetProgress { ProgressView("Preparing…", value: progress) }
        if let error = dictation.languageError {
            Text(error).foregroundStyle(.secondary)
            Button("Retry") { dictation.retryLanguages() }
        }
        Section {
            ModelRow(title: "Language pack · " + ModelRow.size(ModelCatalog.parakeet),
                     model: ModelCatalog.parakeet, dictation: dictation)
            // DESIGN: Native disclosure lists the pack before a download is started.
            DisclosureGroup("Included languages") {
                ForEach(dictation.packLanguages, id: \.identifier) { Text(SpeechLanguage.name($0)) }
            }
        } header: {
            Text("More languages")
        } footer: {
            Text("Adds \(dictation.packLanguages.count) more languages. Runs on this Mac. Speech model by NVIDIA.")
        }
    }

    @ViewBuilder private var polish: some View {
        Section {
            Picker("Default tone", selection: $dictation.tone) {
                ForEach(RewriteTone.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) }
            }
        }
        AppStyleSection(settings: dictation.appStyles, defaultTone: dictation.tone, applications: styleApplications)
        Section {
            Picker("Engine", selection: $dictation.engine) {
                Text(RewriteEngine.apple.title).tag(RewriteEngine.apple)
                Text(dictation.models.isInstalled(ModelCatalog.gemma)
                     ? "Gemma 4" : "Gemma 4 (\(ModelRow.size(ModelCatalog.gemma)) download)")
                    .tag(RewriteEngine.gemma)
            }
            // DESIGN: A native status row reports local engine availability.
            LabeledContent("Status", value: dictation.engine == .gemma && dictation.models.isInstalled(ModelCatalog.gemma)
                ? "Gemma installed" : appleStatus)
            if dictation.engine == .apple, let reason = AppleRewriter.unavailableReason {
                Text(reason).foregroundStyle(.secondary)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(filePath: "/System/Applications/System Settings.app"))
                }
            }
            if dictation.engine == .gemma {
                ModelRow(title: "Gemma 4 · " + ModelRow.size(ModelCatalog.gemma),
                         model: ModelCatalog.gemma, dictation: dictation,
                         footnote: "Until it's downloaded, Refine uses Apple Intelligence.")
            }
            Picker("Output language", selection: $dictation.outputLanguage) {
                Text("Same as spoken").tag(String?.none)
                ForEach(dictation.languages, id: \.self) { identifier in
                    Text(SpeechLanguage.name(Locale(identifier: identifier))).tag(Optional(identifier))
                }
            }
        }
        Section {
            Toggle("Use screen context", isOn: $dictation.useScreenContext)
        } footer: {
            Text("Reads the window you're dictating into to spell names right and understand what you're replying to. Stays on this Mac.")
        }
    }

    @ViewBuilder private var meetings: some View {
        Section {
            Toggle("Show reminder before recording", isOn: $meetingReminder)
            Toggle("Keep recordings' audio", isOn: $meetingAudio)
        }
        Section {
            ModelRow(title: "Speaker detection · " + ModelRow.size(ModelCatalog.meetingDiarizer),
                     model: ModelCatalog.meetingDiarizer, dictation: dictation)
        } footer: {
            Text("Tells the other people in a meeting apart. Runs on this Mac.")
        }
    }

    @ViewBuilder private var privacy: some View {
        Section {
            Picker("Keep history", selection: $dictation.historyRetention) {
                ForEach(HistoryRetention.allCases) { Text($0.title).tag($0) }
            }
            LibraryBackupControls(dictation: dictation, recorder: recorder)
            // DESIGN: Native clear actions name their exact existing scope.
            Button("Clear unedited dictations", role: .destructive) { confirmClear = true }
                .alert("Clear unedited dictations?", isPresented: $confirmClear) {
                    Button("Clear unedited dictations", role: .destructive) { dictation.clearHistory() }
                    Button("Cancel", role: .cancel) {}
                }
            Button("Delete all notes…", role: .destructive) { confirmDeleteAll = true }
                .alert("Delete all notes?", isPresented: $confirmDeleteAll) {
                    Button("Delete all notes", role: .destructive) { dictation.clearHistory(includePinned: true) }
                    Button("Cancel", role: .cancel) {}
                }
        } footer: {
            // DESIGN: Clarify existing privacy copy now that meetings can retain audio by choice.
            Text("Clear unedited dictations keeps meetings and pinned or edited notes. Delete all notes includes pinned and edited notes; meetings are kept. Audio is processed on this Mac and never sent anywhere. Meeting audio is kept when requested or needed to recover a transcript.")
        }
    }

    @ViewBuilder private var about: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NanthAi Scribe").font(.title3.weight(.semibold))
                    Text("Version " + (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                        .foregroundStyle(.secondary)
                }
            }
        }
        Section("Credits") {
            Text("Speech recognition: Apple. Optional language pack: NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0). Optional rewrite model: Google Gemma 4 (Apache 2.0).")
            // DESIGN: Model attribution and licence links use the native Credits section.
            Text("Meeting speakers: " + ModelCatalog.meetingDiarizer.credit + ".")
            Link("Speaker model attribution and licences", destination: URL(string: "https://huggingface.co/\(ModelCatalog.meetingDiarizer.repository)/blob/\(ModelCatalog.meetingDiarizer.revision)/NOTICE.md")!)
            Link("FluidAudio licence", destination: URL(string: "https://github.com/FluidInference/FluidAudio/blob/main/LICENSE")!)
            Link("pyannote licence", destination: URL(string: "https://github.com/pyannote/pyannote-audio/blob/develop/LICENSE")!)
            Link("WeSpeaker licence", destination: URL(string: "https://github.com/wenet-e2e/wespeaker/blob/master/LICENSE")!)
        }
        Section {
            Button("Show onboarding…", action: showOnboarding)
                .buttonStyle(.link)
        }
    }
}

/// Download / progress / pause / delete for one optional model. Downloads only start here.
struct ModelRow: View {
    let title: String
    let model: ModelDescriptor
    let dictation: Dictation
    var footnote: String?
    @State private var confirmDelete = false

    static func size(_ model: ModelDescriptor) -> String {
        ByteCountFormatter.string(fromByteCount: model.expectedTotalSize, countStyle: .file)
    }

    private var progress: ModelStore.Progress {
        dictation.models.progress[model.id] ?? .init(totalBytes: model.expectedTotalSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) { control }
            switch progress.status {
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.secondary)
            case .installed:
                EmptyView()
            default:
                if let footnote { Text(footnote).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .confirmationDialog("Delete \(model.displayName)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { dictation.delete(model) }
        } message: {
            Text("You can download it again later.")
        }
    }

    @ViewBuilder private var control: some View {
        switch progress.status {
        case .absent, .failed:
            Button("Download") { dictation.download(model) }
        case .downloading, .verifying:
            HStack(spacing: 8) {
                ProgressView(value: progress.fraction).frame(width: 120)
                if progress.status == .verifying {
                    Text("Verifying…").foregroundStyle(.secondary)
                } else {
                    Button("Pause") { dictation.pauseDownload(model) }
                }
            }
        case .paused:
            HStack(spacing: 8) {
                ProgressView(value: progress.fraction).frame(width: 120)
                Button("Resume") { dictation.download(model) }
            }
        case .installed:
            HStack(spacing: 8) {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon).foregroundStyle(.secondary)
                Button("Delete", role: .destructive) { confirmDelete = true }
            }
        }
    }
}
