import AppKit
import ScribeCore
import ScribeUI
import SwiftUI
import UniformTypeIdentifiers

/// Kept as a composition for existing offscreen meeting renders; production uses LibraryView.
struct MeetingsView: View {
    @Bindable var recorder: MeetingRecorder
    let dictation: Dictation
    var body: some View {
        NavigationSplitView {
            List(selection: $recorder.selection) { MeetingRows(recorder: recorder) { $0 } }
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            MeetingsDetail(recorder: recorder, dictation: dictation, selection: recorder.selection)
        }.tint(Brand.coral)
    }
}

struct MeetingRows<Tag: Hashable>: View {
    let recorder: MeetingRecorder
    var search = ""
    let tag: (UUID) -> Tag
    private var meetings: [Meeting] {
        recorder.meetings.filter { search.isEmpty || recorder.searchText(for: $0).localizedStandardContains(search) }
    }
    var body: some View {
        // DESIGN: Damaged meeting files use native rows and Delete actions.
        ForEach(recorder.unreadableMeetings) { item in
            HStack {
                Text("Couldn't open this meeting")
                Button("Delete", role: .destructive) { Task { await recorder.delete(item.id) } }
            }
        }
        if let recording = recorder.meetings.first(where: { $0.id == recorder.recordingID }) { row(recording, recording: true) }
        let saved = meetings.filter { $0.id != recorder.recordingID }
        if saved.contains(where: \.pinned) {
            LibraryDateHeader(title: "Pinned")
            ForEach(saved.filter(\.pinned)) { row($0, recording: false) }
        }
        ForEach(MeetingGrouping.days(saved.filter { !$0.pinned })) { day in
            LibraryDateHeader(title: day.title)
            ForEach(day.meetings) { row($0, recording: false) }
        }
    }
    private func row(_ meeting: Meeting, recording: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(meeting.title).lineLimit(1)
            if recording { Text(recorder.paused ? "Paused" : "● Recording").foregroundStyle(recorder.paused ? Color.secondary : Brand.coral) }
            else {
                // DESIGN: Speaker-count metadata copy is unspecified; plain native text.
                Text("\(MeetingTime.stamp(meeting.duration)) · \(meeting.speakers.count) speakers").foregroundStyle(.secondary)
            }
        }.tag(tag(meeting.id))
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { Task { await recorder.delete(meeting.id) } }
        }
        // DESIGN: Native row actions match the iPhone meeting library.
        .swipeActions(edge: .leading) {
            Button(meeting.pinned ? "Unpin" : "Pin", systemImage: meeting.pinned ? "pin.slash" : "pin") {
                recorder.update(meeting.id) { $0.pinned.toggle() }
            }.tint(Brand.amber)
        }
        .contextMenu {
            Button(meeting.pinned ? "Unpin" : "Pin", systemImage: meeting.pinned ? "pin.slash" : "pin") {
                recorder.update(meeting.id) { $0.pinned.toggle() }
            }
            Button("Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(MeetingExport.markdown(meeting), forType: .string)
            }
            Menu("Export", systemImage: "square.and.arrow.up") {
                Button("Markdown") { export(meeting, markdown: true) }
                Button("Plain text") { export(meeting, markdown: false) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { Task { await recorder.delete(meeting.id) } }
        }
    }

    private func export(_ meeting: Meeting, markdown: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [markdown ? UTType(filenameExtension: "md") ?? .plainText : .plainText]
        panel.nameFieldStringValue = meeting.title.replacingOccurrences(of: "/", with: "-") + (markdown ? ".md" : ".txt")
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try (markdown ? MeetingExport.markdown(meeting) : MeetingExport.plainText(meeting))
                    .write(to: url, atomically: true, encoding: .utf8)
            } catch { recorder.error = error.localizedDescription }
        }
    }
}

struct MeetingsDetail: View {
    @Bindable var recorder: MeetingRecorder
    let dictation: Dictation
    let selection: UUID?
    private var selected: Meeting? { recorder.meetings.first { $0.id == selection } }
    var body: some View {
        VStack(spacing: 0) {
            // DESIGN: Start preparation uses a native progress indicator.
            if recorder.starting { ProgressView("Preparing…", value: recorder.assetProgress).padding() }
            // DESIGN: Capture/storage errors use plain native text above the detail.
            if let error = recorder.error { Text(error).foregroundStyle(.secondary).padding() }
            if let meeting = selected {
                if recorder.recordingID == meeting.id {
                    MeetingRecordingView(recorder: recorder)
                } else {
                    MeetingDetailView(meeting: meeting, processing: recorder.processing.contains(meeting.id),
                        progress: recorder.progress[meeting.id],
                        update: { change in recorder.update(meeting.id, change) },
                        updateTitle: { recorder.updateTitle(meeting.id, $0) },
                        updateNotes: { recorder.updateNotes(meeting.id, $0) },
                        regenerate: { recorder.regenerate(meeting.id, dictation: dictation) },
                        retry: { recorder.retryTranscription(meeting.id, dictation: dictation) },
                        audioFolder: recorder.store.directory(meeting.id))
                        .id(meeting.id)
                }
            } else {
                ContentUnavailableView("No meetings yet", systemImage: "waveform",
                    description: Text("Choose Record meeting from the menu bar during a call."))
            }
        }
        .toolbar {
            Menu("Copy", systemImage: "doc.on.doc") {
                Button("Summary") { copy(selected.map(MeetingExport.summary)) }
                Button("Transcript") { copy(selected.map(MeetingExport.transcript)) }
                Button("Everything (Markdown)") { copy(selected.map(MeetingExport.markdown)) }
            }.labelStyle(.titleAndIcon).disabled(selected == nil)
            Menu("Export", systemImage: "square.and.arrow.up") {
                Button("Markdown") { export(markdown: true) }
                Button("Plain text") { export(markdown: false) }
            }.disabled(selected == nil)
            Button("Delete", systemImage: "trash", role: .destructive) {
                if let id = selected?.id { Task { await recorder.delete(id) } }
            }
                .disabled(selected == nil)
        }
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func export(markdown: Bool) {
        guard let selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [markdown ? UTType(filenameExtension: "md") ?? .plainText : .plainText]
        panel.nameFieldStringValue = selected.title.replacingOccurrences(of: "/", with: "-") + (markdown ? ".md" : ".txt")
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try (markdown ? MeetingExport.markdown(selected) : MeetingExport.plainText(selected))
                    .write(to: url, atomically: true, encoding: .utf8)
            } catch { recorder.error = error.localizedDescription }
        }
    }
}

struct MeetingDetailView: View {
    let meeting: Meeting
    var processing = false
    var recording = false
    var progress: MeetingProgress? = nil
    var update: (@escaping (inout Meeting) -> Void) -> Void
    var updateTitle: (String) -> Void
    var updateNotes: ((String) -> Void)? = nil
    var regenerate: () -> Void
    var retry: () -> Void = {}
    var audioFolder: URL?
    var playback: MeetingPlayback? = nil
    @State private var player = MeetingPlayback()
    private var currentPlayer: MeetingPlayback { playback ?? player }

    var body: some View {
        Group {
            if processing {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    MeetingProcessingView(progress: progress ?? .init(identifiesSpeakers: false))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heading
                        if let progress, progress.steps.contains(where: {
                            if case .failed = progress[$0] { return true }; return false
                        }) { MeetingProcessingView(progress: progress).frame(maxWidth: .infinity) }
                        // DESIGN: Recovery and stale-summary actions use native controls.
                        if meeting.canRetryTranscription { Button("Retry transcription", action: retry) }
                        if meeting.summaryNeedsUpdate { Text("Transcript edited · Update summary").foregroundStyle(.secondary) }
                        summary
                        Text("Notes").font(.headline)
                        TextField("Your notes", text: Binding(get: { meeting.notes }, set: { notes in
                            if let updateNotes { updateNotes(notes) } else { update { $0.notes = notes } }
                        }), axis: .vertical)
                            .textFieldStyle(.plain).lineLimit(1...).accessibilityLabel("Notes")
                        // DESIGN: Processing errors outside an active pipeline remain plain native text.
                        if let error = meeting.processingError, progress == nil { Text(error).foregroundStyle(.secondary) }
                        if meeting.summaryError != nil, progress == nil { Text("Couldn't update the summary. Try again.").foregroundStyle(.secondary) }
                        Text("Transcript").font(.headline)
                        if currentPlayer.hasAudio { MeetingPlayerBar(player: currentPlayer) }
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(meeting.turns) { turn in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        MeetingSpeakerButton(name: meeting.speakerName(turn.speakerID),
                                            color: speakerColor(turn.speakerID)) { name in
                                                update { $0.renameSpeaker(turn.speakerID, to: name) }
                                            }
                                        Button(MeetingTime.stamp(turn.start)) { currentPlayer.seek(turn.start) }
                                            .buttonStyle(.plain).monospacedDigit().foregroundStyle(.secondary)
                                            .disabled(!currentPlayer.hasAudio)
                                        if turn.isEdited { Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.tertiary).accessibilityLabel("Edited") }
                                    }
                                    MeetingTurnEditor(turn: turn) { text in update { $0.editTurn(turn.id, text: text) } }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 8)
                                .overlay(alignment: .leading) { if currentPlayer.isActive(turn) { Rectangle().fill(Brand.sky).frame(width: 3) } }
                            }
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { if playback == nil, let audioFolder { player.load(meeting, folder: audioFolder) } }
        .onChange(of: meeting.audio) { _, _ in if playback == nil, let audioFolder { player.load(meeting, folder: audioFolder) } }
        .onDisappear { currentPlayer.stop() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 16) {
            if meeting.recovered {
                Label("Recovered after Scribe quit unexpectedly.", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            TextField("", text: Binding(get: { meeting.title }, set: { updateTitle($0) }))
                .textFieldStyle(.plain).font(.title2.weight(.semibold)).accessibilityLabel("Meeting title")
            // DESIGN: The file creation date is editable with a native date picker.
            DatePicker("Date", selection: Binding(get: { meeting.startedAt }, set: { date in update { $0.startedAt = date } }))
            Text([meeting.startedAt.formatted(date: .abbreviated, time: .shortened),
                  MeetingTime.stamp(meeting.duration), meeting.appName].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Summary").font(.headline)
                Spacer()
                Button("Update summary", action: regenerate).buttonStyle(.borderless).controlSize(.small)
                    .disabled(processing || recording)
            }
            if let summary = meeting.summary {
                if summary.bullets.isEmpty { Text("Too short to summarise.").foregroundStyle(.secondary) }
                ForEach(summary.bullets, id: \.self) { Text("• " + $0) }
                if !summary.actions.isEmpty {
                    Text("Action items").font(.headline)
                    ForEach(summary.actions) { action in
                        Toggle((action.owner.map { $0 + ": " } ?? "") + action.text,
                            isOn: Binding(get: { action.done }, set: { value in
                                update { meeting in
                                    guard let index = meeting.summary?.actions.firstIndex(where: { $0.id == action.id }) else { return }
                                    meeting.summary?.actions[index].done = value
                                }
                            })).toggleStyle(.checkbox)
                    }
                }
            } else if meeting.summaryError == nil && meeting.processingError == nil {
                Text("Too short to summarise.").foregroundStyle(.secondary)
            }
        }
    }
    private func speakerColor(_ id: String) -> Color {
        if id == "you" { return Brand.coral }
        let palette = [Brand.sky, Brand.amber, Brand.coral]
        let index = meeting.speakers.filter { $0.id != "you" }.firstIndex { $0.id == id } ?? 0
        return palette[index % palette.count]
    }
}

private struct MeetingSpeakerButton: View {
    let name: String
    let color: Color
    let rename: (String) -> Void
    @State private var showing = false
    @State private var draft = ""
    var body: some View {
        Button(name) { draft = name; showing = true }
            .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(color)
            .popover(isPresented: $showing) {
                // DESIGN: Rename popover controls and copy are unspecified; native field and button.
                VStack {
                    TextField("Speaker name", text: $draft).onSubmit(save)
                    Button("Rename", action: save).keyboardShortcut(.defaultAction)
                }.padding()
            }
    }
    private func save() { rename(draft); showing = false }
}

struct MeetingConsentView: View {
    var speakerModelInstalled = true
    let start: (Bool, Bool) -> Void
    let cancel: () -> Void
    @State private var dontShow = false
    @State private var tellSpeakersApart = false
    var body: some View {
        // DESIGN: Sheet dimensions and spacing are unspecified; native controls with standard padding.
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording this meeting").font(.headline)
            Text("Ask everyone for permission before you record. Recording laws vary by country.")
                .fixedSize(horizontal: false, vertical: true)
            if !speakerModelInstalled {
                Toggle(isOn: $tellSpeakersApart) {
                    VStack(alignment: .leading) {
                        Text("Tell speakers apart")
                        Text("Downloads 13.7 MB once.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Toggle("Don't show again", isOn: $dontShow).toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Start recording") { start(dontShow, tellSpeakersApart) }.keyboardShortcut(.defaultAction)
            }
        }.padding().frame(width: 440).tint(Brand.coral)
    }
}
