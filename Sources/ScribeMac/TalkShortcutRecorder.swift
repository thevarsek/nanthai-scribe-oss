import AppKit
import Carbon.HIToolbox
import ScribeMacCore
import ScribeUI
import SwiftUI

/// Uses the existing onboarding key-cap treatment without adding shared design tokens.
struct TalkShortcutCaps: View {
    let caps: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(caps, id: \.self) { title in
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .foregroundStyle(Brand.textOnNavy)
                    .background(Brand.navyRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.key))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caps.joined())
    }
}

struct TalkShortcutRow: View {
    @Bindable var dictation: Dictation
    @State private var recording = false

    var body: some View {
        LabeledContent("Talk shortcut") {
            TalkShortcutCaps(caps: dictation.talkShortcut.keyCaps)
            Button("Change…") { recording = true }
                .popover(isPresented: $recording) {
                    TalkShortcutRecorder(dictation: dictation) { shortcut in
                        if let shortcut { dictation.talkShortcut = shortcut }
                        recording = false
                    }
                }
            Menu {
                ForEach(TalkShortcut.presets, id: \.self) { shortcut in
                    Button(shortcut.title) { dictation.talkShortcut = shortcut }
                }
            } label: { Image(systemName: "chevron.down") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Talk shortcut presets")
        }
        .onChange(of: recording) { if !recording { dictation.captureTalkShortcut(nil) } }
        .onDisappear { dictation.captureTalkShortcut(nil) }
    }
}

/// Presentation is separate from input capture so each state can be rendered offscreen.
struct TalkShortcutRecorderContent: View {
    var caps: [String] = []
    var validation: TalkShortcut.Validation = .accepted
    var body: some View {
        // DESIGN: Recorder dimensions and spacing are unspecified; use a plain native popover.
        VStack(alignment: .leading, spacing: 12) {
            Text("Press a key or combination").font(.headline)
            if !caps.isEmpty { TalkShortcutCaps(caps: caps) }
            if let message = validation.message {
                Text(message).foregroundStyle(.secondary)
            }
            Text("Esc to cancel").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 260, alignment: .leading)
    }
}

struct TalkShortcutRecorder: View {
    let dictation: Dictation
    let finish: (TalkShortcut?) -> Void
    @State private var capture = ShortcutCapture()

    var body: some View {
        TalkShortcutRecorderContent(caps: capture.caps, validation: capture.validation)
            .onAppear {
                // Leave the tap callback before saving a shortcut and replacing its run-loop source.
                let complete: (TalkShortcut?) -> Void = { shortcut in
                    Task { @MainActor in finish(shortcut) }
                }
                // The active tap sees system-reserved combinations before macOS consumes them.
                let tapping = dictation.captureTalkShortcut { event in
                    if let event = NSEvent(cgEvent: event) { capture.handle(event, finish: complete) }
                }
                if !tapping { capture.start(finish: complete) }
            }
            .onDisappear {
                dictation.captureTalkShortcut(nil)
                capture.stop()
            }
    }
}

@MainActor
@Observable
final class ShortcutCapture {
    private(set) var caps: [String] = []
    private(set) var validation: TalkShortcut.Validation = .accepted
    private var monitor: Any?
    private var candidate: TalkShortcut?

    func start(finish: @escaping (TalkShortcut?) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event, finish: finish)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func handle(_ event: NSEvent, finish: (TalkShortcut?) -> Void) {
        let flags = event.modifierFlags
        let modifiers = TalkShortcut.Modifiers(event.cgEvent?.flags ?? [])
        if event.type == .keyDown, Int(event.keyCode) == kVK_Escape,
           modifiers.intersection(.primary).isEmpty { finish(nil); return }
        if event.type == .keyDown {
            guard !event.isARepeat else { return }
            let shortcut = TalkShortcut.key(code: event.keyCode, modifiers: modifiers, label: Self.label(event))
            candidate = shortcut
            caps = shortcut.keyCaps
            validation = shortcut.validation
        } else if event.type == .flagsChanged {
            if let candidate, candidate.validation == .accepted {
                // Commit on release so required modifiers are captured before the main key.
                switch candidate {
                case .modifier(let key) where event.keyCode == UInt16(key.keyCode):
                    if !(event.cgEvent?.flags.contains(key.flag) ?? false) { finish(candidate) }
                case .modifier(let key):
                    if !modifiers.subtracting(key.modifiers).isEmpty {
                        self.candidate = nil
                        caps = modifiers.titles
                    }
                default: break
                }
                return
            }
            let key = TalkKey.allCases.first { UInt16($0.keyCode) == event.keyCode }
            if let key, event.cgEvent?.flags.contains(key.flag) == true,
               modifiers.subtracting(key.modifiers).isEmpty {
                candidate = .modifier(key)
                caps = [key.shortcutTitle]
                validation = .accepted
            } else if !flags.intersection([.control, .option, .command, .shift, .function]).isEmpty {
                candidate = nil
                caps = modifiers.titles
                validation = .accepted
            } else if candidate == nil {
                caps = []
                validation = .accepted
            }
        } else if event.type == .keyUp, let candidate,
                  case .key(let code, _, _) = candidate, event.keyCode == code,
                  candidate.validation == .accepted {
            finish(candidate)
        }
    }

    private static func label(_ event: NSEvent) -> String {
        if let index = TalkShortcut.functionKeyCodes.firstIndex(of: event.keyCode) { return "F\(index + 1)" }
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Return: return "Return"
        case kVK_ANSI_KeypadEnter: return "Enter"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        default: return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
    }
}
