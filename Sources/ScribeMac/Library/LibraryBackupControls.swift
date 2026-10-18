import AppKit
import ScribeCore
import SwiftUI

/// DESIGN: Backup actions use native panels and a result alert in History & Privacy.
struct LibraryBackupControls: View {
    let dictation: Dictation
    var recorder: MeetingRecorder?
    @State private var result: String?
    @State private var busy = false
    var body: some View {
        Button("Export Library…") { Task { await exportLibrary() } }.disabled(busy)
        Button("Import Backup…") { Task { await importLibrary() } }.disabled(busy)
            .alert("Library backup", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                Button("OK") { result = nil }
            } message: { Text(result ?? "") }
    }
    private func resolvedRecorder() async -> MeetingRecorder {
        if let recorder { return recorder }
        let recorder = MeetingRecorder(); await recorder.load(); return recorder
    }
    private func snapshot(_ recorder: MeetingRecorder) async throws -> LibraryBackup {
        LibraryBackup(notes: dictation.history, meetings: await recorder.backupMeetings(), dictionary: dictation.dictionary,
                      snippets: dictation.snippets, learning: try dictation.learning.store.load())
    }
    private func exportLibrary() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.scribeBackup]; panel.nameFieldStringValue = "Scribe Library.scribebackup"
        guard await panel.begin() == .OK, let url = panel.url else { return }
        busy = true; defer { busy = false }
        do {
            let recorder = await resolvedRecorder()
            let backup = try await snapshot(recorder)
            try backup.fileWrapper(meetingRoot: recorder.store.root).write(to: url, options: .atomic, originalContentsURL: nil)
            result = "Library exported."
        } catch { result = "Couldn't export the Library. " + error.localizedDescription }
    }
    private func importLibrary() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.scribeBackup]; panel.treatsFilePackagesAsDirectories = false
        guard await panel.begin() == .OK, let url = panel.url else { return }
        busy = true; defer { busy = false }
        do {
            let recorder = await resolvedRecorder()
            let wrapper = try FileWrapper(url: url, options: .immediate)
            let incoming = try LibraryBackup(fileWrapper: wrapper)
            let local = try await snapshot(recorder)
            try incoming.restoreAudio(from: wrapper, local: local.meetings + recorder.deletedMeetings, meetingRoot: recorder.store.root)
            try await recorder.mergeBackupMeetings(incoming.meetings)
            dictation.importNotes(incoming.notes)
            dictation.vocabulary.mergeBackup(dictionary: incoming.dictionary, snippets: incoming.snippets)
            try dictation.learning.store.transaction { $0.merge(incoming.learning) }
            dictation.learning.reload()
            if let failure = dictation.historyFailure ?? dictation.vocabulary.saveFailure { throw BackupFailure(message: failure.message) }
            result = "Backup imported. Your Library has been merged."
        } catch { result = "Couldn't import the backup. " + error.localizedDescription }
    }
}
private struct BackupFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
