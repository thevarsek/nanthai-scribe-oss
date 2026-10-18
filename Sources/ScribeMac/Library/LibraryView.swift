import AppKit
import ScribeCore
import ScribeUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class LibraryNavigation {
    enum Selection: Hashable { case note(UUID), meeting(UUID), meetings }
    var selection: Selection?
}

struct LibraryView: View {
    let dictation: Dictation
    let recorder: MeetingRecorder
    @Bindable var navigation: LibraryNavigation
    var editorOverride: NoteEditor? = nil
    @State private var importedURL: URL?
    @State private var showImportConsent = false
    @State private var search: String

    init(dictation: Dictation, recorder: MeetingRecorder, navigation: LibraryNavigation,
         editorOverride: NoteEditor? = nil, search: String = "") {
        self.dictation = dictation
        self.recorder = recorder
        self.navigation = navigation
        self.editorOverride = editorOverride
        _search = State(initialValue: search)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                HStack(spacing: 8) {
                    TrioMark().frame(width: 18, height: 18)
                    Text("Scribe").font(.system(size: 13, weight: .semibold))
                }.padding(12).selectionDisabled()
                Section("Library") {
                    // DESIGN: Unreadable notes remain individually deletable in Library.
                    ForEach(dictation.unreadableNotes) { item in
                        HStack {
                            Text("Couldn't open this note")
                            Button("Delete", role: .destructive) { dictation.deleteUnreadableNote(item.id) }
                        }
                    }
                    ForEach(NoteSection.sections(dictation.history, search: search)) { section in
                        LibraryDateHeader(title: section.title)
                        ForEach(section.notes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title).font(.system(size: 13)).lineLimit(1)
                                HStack(spacing: 4) {
                                    if note.isEdited { Image(systemName: "pencil.and.scribble").font(.system(size: 11)) }
                                    Text(note.createdAt, format: .dateTime.hour().minute()).font(.system(size: 11))
                                }.foregroundStyle(.secondary)
                            }.tag(LibraryNavigation.Selection.note(note.id))
                            .swipeActions(edge: .leading) {
                                Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") {
                                    togglePin(note)
                                }.tint(Brand.amber)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(note) }
                            }
                            .contextMenu {
                                Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") { togglePin(note) }
                                Button("Copy", systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(note.text, forType: .string)
                                }
                                // DESIGN: Native sharing exports the note's current plain text.
                                ShareLink(item: note.text) { Label("Share", systemImage: "square.and.arrow.up") }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(note) }
                            }
                        }
                    }
                }
                if !search.isEmpty, NoteSection.sections(dictation.history, search: search).isEmpty,
                   !recorder.meetings.contains(where: { recorder.searchText(for: $0).localizedStandardContains(search) }) {
                    // DESIGN: A native no-results view offers the requested search reset.
                    ContentUnavailableView {
                        Label("No results for “\(search)”", systemImage: "magnifyingglass")
                    } actions: { Button("Clear search") { search = "" } }
                }
                Divider()
                Section {
                    if recorder.meetings.isEmpty { Text("Meetings").tag(LibraryNavigation.Selection.meetings) }
                    MeetingRows(recorder: recorder, search: search) { LibraryNavigation.Selection.meeting($0) }
                } header: { Text("Meetings") }
                RecentlyDeletedSection(notes: dictation.deletedNotes, meetings: recorder.deletedMeetings,
                    restoreNote: dictation.restoreNote, deleteNote: dictation.deleteNoteNow,
                    restoreMeeting: { id in Task { await recorder.restore(id, options: .init(dictation: dictation)) } },
                    deleteMeeting: { id in Task { await recorder.deleteNow(id) } })
            }
            .searchable(text: $search, prompt: "Search Library")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            switch navigation.selection {
            case .note(let id):
                if let note = dictation.history.first(where: { $0.id == id }) {
                    MacNoteEditorView(note: note, dictation: dictation, navigation: navigation, editor: editorOverride).id(id)
                }
            case .meeting(let id):
                MeetingsDetail(recorder: recorder, dictation: dictation, selection: id)
            case .meetings:
                MeetingsDetail(recorder: recorder, dictation: dictation, selection: nil)
            case nil:
                // DESIGN: The empty detail uses a native placeholder and standard New Note action.
                ContentUnavailableView {
                    Label("Library", systemImage: "note.text")
                } description: { Text("Select a note or create a new one.") } actions: {
                    Button("New Note") { create() }
                }
            }
        }
        .modifier(SaveFailureNotice(failure: dictation.historyFailure, retry: dictation.retrySaveNotes))
        .frame(minWidth: 720, minHeight: 460)
        .tint(Brand.coral)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button("New Note", systemImage: "square.and.pencil", action: create).keyboardShortcut("n")
                    Button("Paste as New Note", systemImage: "doc.on.clipboard", action: paste)
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                } primaryAction: { create() }
                .labelStyle(.titleAndIcon).keyboardShortcut("n")
                .help("New Note (⌘N)").accessibilityLabel("New Note")
            }
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button(recorder.isRecording ? "Stop recording" : "Record meeting", action: record)
                    Button("Transcribe a Recording…", action: chooseRecording)
                } label: {
                    Label {
                        Text(recorder.starting ? "Preparing…" : recorder.isRecording ? "Stop" : "Record")
                    } icon: {
                        Image(systemName: recorder.isRecording ? "stop.circle" : "record.circle")
                            .foregroundStyle(recorder.isRecording ? Brand.coral : Color.primary)
                    }
                } primaryAction: { record() }
                .labelStyle(.titleAndIcon).keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(recorder.starting)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in offerImport(url) }
            }
            return true
        }
        .sheet(isPresented: $showImportConsent) {
            RecordingImportConsent(speakerModelInstalled: dictation.models.isInstalled(ModelCatalog.meetingDiarizer)) { speakers in
                guard let url = importedURL else { return }
                showImportConsent = false; importedURL = nil
                Task { await recorder.importRecording(url, dictation: dictation, tellSpeakersApart: speakers) }
            } cancel: { showImportConsent = false; importedURL = nil }
        }
        .alert("Recording", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
            Button("OK") { recorder.error = nil }
        } message: { Text(recorder.error ?? "") }
        .navigationTitle(windowTitle)
        .onChange(of: recorder.selection) { _, id in if let id { navigation.selection = .meeting(id) } }
        .sheet(isPresented: Binding(get: { recorder.showConsent }, set: { recorder.showConsent = $0 })) {
            MeetingConsentView(speakerModelInstalled: dictation.models.isInstalled(ModelCatalog.meetingDiarizer)) { dontShow, tellSpeakersApart in
                if dontShow { recorder.showReminder = false }
                recorder.showConsent = false
                Task { await recorder.start(dictation: dictation, tellSpeakersApart: tellSpeakersApart) }
            } cancel: { recorder.showConsent = false }
        }
    }

    private func chooseRecording() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = RecordingImport.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.begin { result in if result == .OK, let url = panel.url { offerImport(url) } }
    }
    private func offerImport(_ url: URL) {
        guard RecordingImport.extensions.contains(url.pathExtension.lowercased()) else { return }
        importedURL = url; showImportConsent = true
    }
    private func record() {
        if let id = recorder.recordingID { navigation.selection = .meeting(id); Task { await recorder.stop() } }
        else if recorder.showReminder { recorder.requestStart() }
        else { Task { await recorder.start(dictation: dictation) } }
    }

    private var windowTitle: String {
        guard case .note(let id) = navigation.selection,
              let note = dictation.history.first(where: { $0.id == id }) else { return "Scribe" }
        return String(note.title.prefix(40))
    }
    private func togglePin(_ note: Note) {
        var updated = note
        updated.pinned.toggle()
        updated.modified = .now
        dictation.saveNote(updated)
    }
    private func delete(_ note: Note) {
        if navigation.selection == .note(note.id) { navigation.selection = nil }
        dictation.deleteNote(note.id)
    }
    private func create() { navigation.selection = .note(dictation.createNote().id) }
    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        navigation.selection = .note(dictation.createNote(text: text, origin: .pasted).id)
    }
}

/// Date labels are subordinate to Library and Meetings and never participate in selection.
struct LibraryDateHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 12).padding(.bottom, 4)
            .listRowInsets(.vertical, 0)
            .selectionDisabled()
            .accessibilityAddTraits(.isHeader)
    }
}

struct MacNoteEditorView: View {
    let dictation: Dictation
    let navigation: LibraryNavigation
    @State private var editor: NoteEditor
    @State private var confirmRevert = false

    init(note: Note, dictation: Dictation, navigation: LibraryNavigation, editor: NoteEditor? = nil) {
        self.dictation = dictation
        self.navigation = navigation
        _editor = State(initialValue: editor ?? NoteEditor(note: note, autosave: { dictation.saveNote($0) },
            currentNote: { id in dictation.history.first { $0.id == id } }))
    }

    var body: some View {
        VStack(spacing: 0) {
            MacNoteTextEditor(editor: editor).frame(maxWidth: 728).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                if let failure = editor.failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if editor.isRunning { BusyRing().frame(width: 20, height: 20).accessibilityLabel("Refining…") }
                        ForEach(RewritePrompts.Preset.allCases, id: \.rawValue) { preset in
                            if preset == .translate {
                                // DESIGN: The native menu keeps the resolved translation target editable here.
                                Menu {
                                    Picker("Translate to", selection: Binding(get: { dictation.outputLanguage ?? "" }, set: { dictation.outputLanguage = $0.isEmpty ? nil : $0 })) {
                                        Text("Automatic").tag("")
                                        ForEach(dictation.languages, id: \.self) { identifier in
                                            Text(SpeechLanguage.name(Locale(identifier: identifier))).tag(identifier)
                                        }
                                    }
                                } label: { RefinePresetChip(RefinePresentation.translateLabel(text: translationText, outputLanguage: dictation.outputLanguage ?? "", languages: dictation.languages)) } primaryAction: { apply(preset) }
                                .disabled(editor.isRunning || editor.text.isEmpty || editor.showChanges)
                            } else {
                                Button { apply(preset) } label: { RefinePresetChip(preset.rawValue.capitalized) }
                                    .disabled(editor.isRunning || editor.text.isEmpty || editor.showChanges)
                            }
                        }
                        if editor.hasChanges || editor.showChanges {
                            Button { editor.showChanges.toggle() } label: { RefinePresetChip("Show changes").foregroundStyle(editor.showChanges ? Brand.amber : Color.primary) }
                                .accessibilityValue(editor.showChanges ? "On" : "Off")
                        }
                    }.buttonStyle(.plain).padding(.trailing, 16)
                }
            }.padding(16)
        }
        // DESIGN: Revert uses the requested confirmation with a native dialog.
        .confirmationDialog("Revert to original?", isPresented: $confirmRevert) {
            Button("Revert to Original", role: .destructive) { editor.revert() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Replace this note with its original text? You can undo this change.") }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editor.text, forType: .string)
                }.labelStyle(.titleAndIcon).keyboardShortcut("c", modifiers: [.command, .shift])
                    .help("Copy (⇧⌘C)").accessibilityLabel("Copy")
                // DESIGN: Native Share uses the current editor text, including unsaved changes.
                ShareLink(item: editor.text) { Label("Share", systemImage: "square.and.arrow.up") }
                Menu {
                    Button("Save as Copy", action: saveCopy).keyboardShortcut("s", modifiers: [.command, .option])
                    Toggle("Show changes", isOn: $editor.showChanges)
                    Button("Revert to Original") { confirmRevert = true }
                    Button("Delete", role: .destructive) {
                        editor.cancel()
                        editor.autosave = nil
                        dictation.deleteNote(editor.original.id)
                        navigation.selection = nil
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .help("Note actions").accessibilityLabel("Note actions")
            }
        }
    }

    private var translationText: String {
        if editor.selection.length > 0, let range = Range(editor.selection, in: editor.text) {
            return String(editor.text[range])
        }
        return editor.text
    }

    private func apply(_ preset: RewritePrompts.Preset) {
        Task {
            await editor.apply(preset, rewriter: dictation.rewriter(), tone: dictation.tone,
                outputLanguage: dictation.outputLanguage ?? "", languages: dictation.languages, dictionary: dictation.dictionary)
        }
    }
    private func saveCopy() {
        let copy = editor.saveAsCopy()
        navigation.selection = .note(copy.id)
    }
}

/// Observes only the Library window; the menu-bar app remains alive after it closes.
struct LibraryWindowLifecycle: NSViewRepresentable {
    let recorder: MeetingRecorder
    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.recorder = recorder
        return view
    }
    func updateNSView(_ nsView: WindowObserverView, context: Context) {}

    @MainActor final class WindowObserverView: NSView {
        var recorder: MeetingRecorder?
        private var closeObserver: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            NSApp.setActivationPolicy(.regular)
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.recorder?.showConsent = false
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
        }
        isolated deinit { if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) } }
    }
}
