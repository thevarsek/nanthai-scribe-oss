import ScribeCore
import SwiftUI

@MainActor private enum PresentedSaveFailures {
    static var ids: Set<UUID> = []
}

/// A failure stays acknowledged across editor/window recreation until saving succeeds.
struct SaveFailureNotice: ViewModifier {
    let failure: SaveFailure?
    let retry: () -> Void
    @State private var presented: SaveFailure?
    func body(content: Content) -> some View {
        content.onChange(of: failure?.id, initial: true) { _, _ in
            if let failure, PresentedSaveFailures.ids.insert(failure.id).inserted { presented = failure }
        }
        // DESIGN: Persistence failures use a native alert with optional Retry; editing continues.
        .alert("Couldn't save", isPresented: Binding(get: { presented != nil }, set: { if !$0 { presented = nil } })) {
            Button("Retry", action: retry)
            Button("OK", role: .cancel) {}
        } message: { Text(presented?.message ?? "") }
    }
}
