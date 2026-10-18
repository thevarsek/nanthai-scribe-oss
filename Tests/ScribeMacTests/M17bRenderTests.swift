import AppKit
import ScribeCore
import ScreenCaptureKit
import SwiftUI
import Testing
@testable import ScribeMac

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRIBE_M17B_RENDER_DIR"] != nil))
struct M17bRenderTests {
    @Test func renderAllMeetingStates() async throws {
        let destination = URL(filePath: try #require(ProcessInfo.processInfo.environment["SCRIBE_M17B_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let domain = "M17bRenders-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let root = destination.appending(path: "fixtures")
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        let dictation = Dictation(defaults: defaults, historyURL: root.appending(path: "history.json"), vocabularyDirectory: root)
        let recorder = MeetingRecorder(root: root.appending(path: "meetings"), defaults: defaults)
        let navigation = LibraryNavigation()
        let meeting = Meeting(title: "Product review", duration: 1284,
            speakers: [.init(id: "you", name: "You"), .init(id: "a", name: "Sam")],
            turns: [.init(speakerID: "a", start: 0, end: 9, text: "The prototype is ready. Let's review accessibility before Friday's launch."),
                    .init(speakerID: "you", start: 10, end: 18, text: "I'll arrange the review for Thursday and invite the support team.")],
            summary: .init(bullets: ["The prototype is ready for review.", "Launch is planned for Friday."],
                actions: [.init(text: "Arrange Thursday's review", owner: "You")]),
            notes: "Check keyboard navigation with the support team.\n日本語 · العربية · italiano")
        for scheme in [ColorScheme.light, .dark] {
            NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let suffix = scheme == .light ? "light" : "dark"
            func shot(_ name: String) -> URL { destination.appending(path: "\(name)-\(suffix).png") }
            recorder.meetings = []; navigation.selection = .meetings
            try await render(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation)
                .frame(width: 900, height: 600), scheme: scheme, to: shot("idle"), chrome: true)
            for (name, mic, call, paused) in [
                ("recording", MeetingSourceHealth.level(0.06), MeetingSourceHealth.level(0.1), false),
                ("mic-warning", .warning("Reconnecting…"), .level(0.08), false),
                ("in-person", .level(0.04), .none, false),
                ("paused", .paused, .paused, true)
            ] {
                try await render(MeetingRecordingContent(elapsed: 724, paused: paused,
                    microphone: mic, callAudio: call, pause: {}, stop: {}).frame(width: 660, height: 560),
                    scheme: scheme, to: shot(name))
            }
            let progress = MeetingProgress(identifiesSpeakers: true,
                statuses: [.saving: .done, .transcribing: .active])
            try await render(detail(meeting, processing: true, progress: progress).frame(width: 660, height: 560),
                scheme: scheme, to: shot("processing"))
            let failed = MeetingProgress(identifiesSpeakers: false,
                statuses: [.saving: .done, .transcribing: .failed("The microphone stopped delivering audio.")])
            try await render(detail(meeting, processing: true, progress: failed).frame(width: 660, height: 560),
                scheme: scheme, to: shot("processing-failed"))
            recorder.meetings = [meeting]; navigation.selection = .meeting(meeting.id)
            try await render(LibraryView(dictation: dictation, recorder: recorder, navigation: navigation)
                .frame(width: 960, height: 760), scheme: scheme, to: shot("done"), chrome: true)
            var edited = meeting
            edited.editTurn(edited.turns[0].id, text: "The prototype is ready. Accessibility review is on Thursday.")
            try await render(detail(edited).frame(width: 660, height: 760), scheme: scheme, to: shot("edited-turn"))
            var recovered = meeting; recovered.recovered = true
            try await render(detail(recovered).frame(width: 660, height: 760), scheme: scheme, to: shot("recovered"))
            let short = Meeting(title: "Quick check-in", duration: 3, summary: .init(bullets: []))
            try await render(detail(short).frame(width: 660, height: 560), scheme: scheme, to: shot("too-short"))
            try await render(MeetingConsentView(speakerModelInstalled: false, start: { _, _ in }, cancel: {}),
                scheme: scheme, to: shot("consent"))
        }
    }

    @Test func editingBoundaryHandlesCancelSaveAndClickAway() throws {
        _ = NSApplication.shared
        var commits = 0, cancels = 0
        let boundary = MeetingEditBoundary.BoundaryView(commit: { commits += 1 }, cancel: { cancels += 1 })
        boundary.frame = NSRect(x: 20, y: 20, width: 200, height: 80)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(boundary)
        defer { boundary.removeObservers(); window.close() }
        func key(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            NSApp.sendEvent(event)
        }
        try key(53, "\u{1b}")
        #expect(cancels == 1 && commits == 0)
        try key(36, "\r", modifiers: [.command])
        #expect(commits == 1)
        func click(_ point: NSPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
        }
        try click(NSPoint(x: 30, y: 30))
        #expect(commits == 1)
        try click(NSPoint(x: 350, y: 150))
        #expect(commits == 2)
        boundary.removeObservers()
        try key(53, "\u{1b}")
        #expect(cancels == 1)
    }

    private func detail(_ meeting: Meeting, processing: Bool = false, progress: MeetingProgress? = nil) -> some View {
        MeetingDetailView(meeting: meeting, processing: processing, progress: progress,
            update: { _ in }, updateTitle: { _ in }, regenerate: {})
    }

    private func render(_ view: some View, scheme: ColorScheme, to url: URL, chrome: Bool = false) async throws {
        // Native multiline fields need an offscreen AppKit pass before ImageRenderer exports them.
        let controller = NSHostingController(rootView: view.environment(\.colorScheme, scheme).environment(\.appearsActive, true))
        let host = controller.view
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Scribe"
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentViewController = controller
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        window.makeFirstResponder(nil)
        let snapshot: NSImage
        let captureSize: NSSize
        if chrome {
            // Only this generated offscreen window is captured; native toolbars are WindowServer layers.
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let target = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * 2); configuration.height = Int(window.frame.height * 2)
            configuration.showsCursor = false; configuration.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
            captureSize = window.frame.size
            snapshot = NSImage(cgImage: image, size: captureSize)
        } else {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            captureSize = size
            snapshot = NSImage(size: size); snapshot.addRepresentation(bitmap)
        }
        let renderer = ImageRenderer(content: ZStack {
            Color(nsColor: .windowBackgroundColor)
            Image(nsImage: snapshot)
        }.frame(width: captureSize.width, height: captureSize.height).environment(\.colorScheme, scheme))
        renderer.scale = 2
        let png = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        try #require(png.representation(using: .png, properties: [:])).write(to: url)
    }
}
