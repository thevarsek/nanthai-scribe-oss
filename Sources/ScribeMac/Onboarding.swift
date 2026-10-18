import AppKit
import ApplicationServices
import ScribeCore
import ScribeMacCore
import ScribeUI
import SwiftUI

@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private let dictation: Dictation
    private let permissions: Permissions
    private let settings: MacSettings

    init(dictation: Dictation, permissions: Permissions, settings: MacSettings = MacSettings()) {
        self.dictation = dictation
        self.permissions = permissions
        self.settings = settings
    }

    func showIfNeeded() {
        if !settings.onboardingDone { show() }
    }

    func show() {
        if let window, window.isVisible {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "NanthAi Scribe"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView:
            OnboardingView(dictation: dictation, permissions: permissions) { [weak self] in
                self?.settings.onboardingDone = true
                self?.window?.close()
            }
        )
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    let dictation: Dictation
    let permissions: Permissions
    var done: () -> Void
    @State private var step: OnboardingStep = .welcome
    @State private var microphoneGranted = false
    @State private var requestingMicrophone = false

    var body: some View {
        OnboardingPage(step: step, talkShortcut: dictation.talkShortcut,
                       accessibilityGranted: permissions.accessibility,
                       microphoneGranted: microphoneGranted,
                       requestingMicrophone: requestingMicrophone,
                       action: advance)
        .task(id: step) {
            guard step == .accessibility else { return }
            while !Task.isCancelled {
                permissions.refresh()
                if permissions.accessibility {
                    dictation.arm()
                    // Keep the granted checkmark visible for one polling interval.
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    step = .microphone
                    return
                }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    private func advance() {
        switch step {
        case .welcome: step = .accessibility
        case .accessibility:
            permissions.promptAccessibility()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        case .microphone:
            guard !requestingMicrophone else { return }
            requestingMicrophone = true
            Task {
                microphoneGranted = await Microphone.requestAccess()
                requestingMicrophone = false
                if microphoneGranted {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    step = .tryIt
                }
            }
        case .tryIt: done()
        }
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, accessibility, microphone, tryIt
    var id: Int { rawValue }
}

/// This page has no permission side effects, so all four states can be rendered offscreen.
struct OnboardingPage: View {
    let step: OnboardingStep
    var talkShortcut: TalkShortcut = .rightOption
    var accessibilityGranted = false
    var microphoneGranted = false
    var requestingMicrophone = false
    var action: () -> Void = {}
    @State private var testText = ""
    @FocusState private var testFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            // DESIGN: Dot size and spacing are unspecified; use simple dots in existing text tokens.
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { item in
                    Circle().fill(item == step ? Brand.textOnNavy : Brand.secondaryOnNavy)
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        // DESIGN: Use native default text sizes and plain spacing where no typography is specified.
        .padding(32)
        .frame(width: 480, height: 420)
        .foregroundStyle(Brand.textOnNavy)
        .multilineTextAlignment(.center)
        .background(Brand.navy)
        .tint(Brand.coral)
        .buttonStyle(.borderedProminent)
        // DESIGN: Keep native controls legible on the specified navy surface in either system appearance.
        .environment(\.colorScheme, .dark)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.title2.weight(.semibold))
    }

    private var granted: some View {
        Label("Allowed", systemImage: "checkmark.circle.fill")
            .font(.body.weight(.medium))
            .foregroundStyle(Brand.cyan)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            title("Dictate anywhere on your Mac")
            Text("Hold a key, talk, release. Your words appear wherever you're typing.")
                .foregroundStyle(Brand.secondaryOnNavy)
            Button("Continue", action: action)
        case .accessibility:
            title("Allow Accessibility")
            Text("Lets Scribe notice the dictation key and type for you.")
                .foregroundStyle(Brand.secondaryOnNavy)
            if accessibilityGranted { granted } else { Button("Open System Settings", action: action) }
        case .microphone:
            title("Allow the microphone")
            if microphoneGranted { granted } else { Button("Allow", action: action).disabled(requestingMicrophone) }
        case .tryIt:
            title("Try it")
            Text(talkShortcut.title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 28).padding(.vertical, 20)
                .background(Brand.navyRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.key))
            Text("Hold it and say something.").foregroundStyle(Brand.secondaryOnNavy)
            TextField("Your words appear here", text: $testText)
                .textFieldStyle(.plain)
                .font(Brand.Font.hud)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Brand.navyRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.key))
                .accessibilityLabel("Try it")
                .focused($testFocused)
                .defaultFocus($testFocused, true)
            Button("Done", action: action)
        }
    }
}
