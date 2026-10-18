import AppKit
import ApplicationServices
import ScribeCore
import SwiftUI

@main
struct ScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(dictation: delegate.dictation, recorder: delegate.meetings, navigation: delegate.libraryNavigation, updates: delegate.updates)
        } label: {
            Image(nsImage: MenuBarIcon.image(listening: delegate.dictation.phase == .listening, recording: delegate.meetings.isRecording))
        }
        Window("Scribe", id: "library") {
            LibraryView(dictation: delegate.dictation, recorder: delegate.meetings, navigation: delegate.libraryNavigation)
                .background(LibraryWindowLifecycle(recorder: delegate.meetings))
        }
        .defaultSize(width: 900, height: 600)
        .defaultLaunchBehavior(.suppressed)
        Settings {
            SettingsView(dictation: delegate.dictation, showOnboarding: delegate.showOnboarding, recorder: delegate.meetings, updates: delegate.updates)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { delegate.updates.checkForUpdates() }
            }
        }
    }
}

@MainActor
@Observable
final class Permissions {
    private(set) var accessibility = AXIsProcessTrusted()

    func promptAccessibility() {
        // The documented value of kAXTrustedCheckOptionPrompt; the global itself isn't concurrency-safe.
        let key = "AXTrustedCheckOptionPrompt"
        accessibility = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func refresh() { accessibility = AXIsProcessTrusted() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updates = Updates()
    let dictation = Dictation()
    let permissions = Permissions()
    let meetings = MeetingRecorder()
    let libraryNavigation = LibraryNavigation()
    private var hud: HUDController?
    private var onboarding: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hud = HUDController(dictation: dictation)
        Task {
            await meetings.load()
            meetings.recover(options: .init(dictation: dictation))
        }

        onboarding = OnboardingController(dictation: dictation, permissions: permissions)
        onboarding?.showIfNeeded()
        dictation.arm()

        // The tap can only be created once Accessibility is granted; keep trying until then,
        // so granting it in System Settings takes effect without a relaunch.
        Task {
            while !dictation.arm() {
                try? await Task.sleep(for: .seconds(1.5))
                permissions.refresh()
            }
            permissions.refresh()
        }

        // Discover locally; downloads begin only from a language or recording action.
        Task { await dictation.loadLanguages() }
    }

    func showOnboarding() { onboarding?.show() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await meetings.finishBeforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct MenuContent: View {
    @Bindable var dictation: Dictation
    @Bindable var recorder: MeetingRecorder
    let navigation: LibraryNavigation
    var updates: Updates?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private func showLibrary() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "library")
        NSApp.activate()
    }
    private func showMeetings() {
        navigation.selection = recorder.selection.map(LibraryNavigation.Selection.meeting) ?? .meetings
        showLibrary()
    }

    var body: some View {
        Button {
            showMeetings()
            if recorder.isRecording { Task { await recorder.stop() } }
            else if recorder.showReminder { recorder.requestStart() }
            else { Task { await recorder.start(dictation: dictation) } }
        } label: {
            Label(recorder.isRecording ? "Stop recording · " + MeetingTime.stamp(recorder.elapsed) : "Record meeting",
                  systemImage: "record.circle")
        }.disabled(recorder.starting)
        if recorder.isRecording {
            Button(recorder.paused ? "Resume recording" : "Pause recording") {
                Task { await recorder.togglePause() }
            }.disabled(recorder.changingPause)
        }
        Divider()
        Text("Hold \(dictation.talkShortcut.title) to dictate")
            .disabled(true)
        Text("⌘ while holding: Refine · Shift: hands-free")
            .font(.system(size: NSFont.smallSystemFontSize))
            .disabled(true)
        Divider()

        Button("Open Scribe…") { showLibrary() }.keyboardShortcut("o")
        // DESIGN: Recovery uses plain native menu actions, independent of history retention.
        Button("Paste Last Dictation") { dictation.pasteLastDictation() }
            .disabled(dictation.lastDictation == nil)
        ForEach(dictation.retryTakes) { take in
            Button("Retry transcription") { dictation.retryTranscription(take) }
        }
        Menu("Recent") {
            if dictation.history.isEmpty {
                Text("Nothing yet")
            } else {
                ForEach(dictation.history.prefix(10)) { entry in
                    Button(entry.text.count > 60 ? entry.text.prefix(60) + "…" : entry.text) {
                        dictation.copy(entry)
                    }
                }
            }
        }

        Menu("Languages: \(dictation.languages.map { SpeechLanguage.shortName(Locale(identifier: $0)) }.joined(separator: ", "))") {
            Text(dictation.languages.count > 1
                 ? "Detects which one you're speaking"
                 : "Pick up to \(Dictation.maxLanguages) to auto-detect")
            Divider()
            ForEach(dictation.availableLanguages, id: \.identifier) { locale in
                Toggle(SpeechLanguage.name(locale), isOn: Binding(
                    get: { dictation.isSelected(locale) },
                    set: { _ in dictation.toggle(locale) }
                ))
            }
        }
        Picker("Output language: \(dictation.outputLanguage.map { SpeechLanguage.name(Locale(identifier: $0)) } ?? "Same as spoken")",
               selection: $dictation.outputLanguage) {
            Text("Same as spoken").tag(String?.none)
            ForEach(dictation.languages, id: \.self) { identifier in
                Text(SpeechLanguage.name(Locale(identifier: identifier))).tag(Optional(identifier))
            }
        }
        .pickerStyle(.menu)

        Divider()
        Button("Settings…") {
            NSApp.activate()
            // The Settings scene brings its singleton window to the front on every open.
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Check for Updates…") { updates?.checkForUpdates() }
        Button("Quit NanthAi Scribe") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
