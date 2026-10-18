import ScribeCore
import SwiftUI

/// DESIGN: Imports reuse the meeting reminder copy with native Transcribe and Cancel actions.
struct RecordingImportConsent: View {
    let speakerModelInstalled: Bool
    let start: (Bool) -> Void
    let cancel: () -> Void
    @State private var speakers = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcribe a recording").font(.headline)
            Text("Ask everyone for permission before you record. Recording laws vary by country.")
            if !speakerModelInstalled {
                Toggle("Tell speakers apart", isOn: $speakers)
                Text("Downloads 13.7 MB once.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Transcribe") { start(speakers) }.keyboardShortcut(.defaultAction)
            }
        }.padding().frame(width: 440)
    }
}
