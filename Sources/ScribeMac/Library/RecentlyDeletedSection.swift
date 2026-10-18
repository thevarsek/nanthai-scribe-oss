import ScribeCore
import SwiftUI

/// DESIGN: Recently Deleted uses native section rows, action buttons and a header menu.
struct RecentlyDeletedSection: View {
    let notes: [Note]
    let meetings: [Meeting]
    let restoreNote: (UUID) -> Void
    let deleteNote: (UUID) -> Void
    let restoreMeeting: (UUID) -> Void
    let deleteMeeting: (UUID) -> Void
    var body: some View {
        Section {
            if notes.isEmpty && meetings.isEmpty { Text("No recently deleted items").foregroundStyle(.secondary) }
            ForEach(notes) { note in
                row(note.title, deletedAt: note.deletedAt, restore: { restoreNote(note.id) }, delete: { deleteNote(note.id) })
            }
            ForEach(meetings) { meeting in
                row(meeting.title, deletedAt: meeting.deletedAt, restore: { restoreMeeting(meeting.id) }, delete: { deleteMeeting(meeting.id) })
            }
        } header: {
            HStack {
                Text("Recently Deleted")
                Spacer()
                Menu("Recently Deleted actions", systemImage: "ellipsis.circle") {
                    Button("Delete All", role: .destructive) {
                        for note in notes { deleteNote(note.id) }
                        for meeting in meetings { deleteMeeting(meeting.id) }
                    }.disabled(notes.isEmpty && meetings.isEmpty)
                }.labelStyle(.iconOnly)
            }
        }
    }
    private func row(_ title: String, deletedAt: Date?, restore: @escaping () -> Void, delete: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).lineLimit(1)
            if let deletedAt {
                Text("Deleted " + deletedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Restore", action: restore)
                Button("Delete Now", role: .destructive, action: delete)
            }.buttonStyle(.borderless)
        }.contextMenu {
            Button("Restore", action: restore)
            Button("Delete Now", role: .destructive, action: delete)
        }
    }
}
