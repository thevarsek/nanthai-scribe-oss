import AppKit
import ScribeCore
import SwiftUI

struct MeetingTurnEditor: View {
    let turn: MeetingTurn
    let save: (String) -> Void
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...).focused($editorFocused)
                    .accessibilityLabel("Transcript turn")
                    .onChange(of: editorFocused) { _, focused in if !focused { commit() } }
                    .task { editorFocused = true }
            } else {
                Text(turn.text).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled).focusable()
                    .onTapGesture(count: 2, perform: begin)
                    .onKeyPress(.return) { begin(); return .handled }
                    .accessibilityAction(named: "Edit transcript turn", begin)
            }
        }
        .background { if editing { MeetingEditBoundary(commit: commit, cancel: cancel) } }
        .onDisappear { commit() }
    }
    private func begin() { draft = turn.text; editing = true }
    private func cancel() { editing = false; editorFocused = false }
    private func commit() {
        guard editing else { return }
        editing = false; editorFocused = false
        if draft != turn.text { save(draft) }
    }
}


/// Native fields keep focus when clicking a non-focusable label or blank space. Commit before
/// that click is delivered, including clicks in the sidebar, without consuming the user's action.
/// Key monitoring handles Escape and Command-Return before the native multiline field consumes them.
struct MeetingEditBoundary: NSViewRepresentable {
    let commit: () -> Void
    let cancel: () -> Void
    func makeNSView(context: Context) -> BoundaryView { BoundaryView(commit: commit, cancel: cancel) }
    func updateNSView(_ view: BoundaryView, context: Context) { view.commit = commit; view.cancel = cancel }
    static func dismantleNSView(_ view: BoundaryView, coordinator: ()) { view.removeObservers() }

    final class BoundaryView: NSView {
        var commit: () -> Void
        var cancel: () -> Void
        private var monitor: Any?
        private var observer: NSObjectProtocol?
        init(commit: @escaping () -> Void, cancel: @escaping () -> Void) {
            self.commit = commit; self.cancel = cancel
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { return nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self else { return false }
                    if event.type == .keyDown {
                        guard event.window === self.window else { return false }
                        if event.keyCode == 53 { self.cancel(); return true }
                        if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command) {
                            self.commit(); return true
                        }
                        return false
                    }
                    if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                        self.commit()
                    }
                    return false
                }
                return handled ? nil : event
            }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.commit() }
                }
        }
        func removeObservers() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            monitor = nil; observer = nil
        }
    }
}
