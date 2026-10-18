import AppKit
import ScribeUI
import SwiftUI

/// Floating bar shown while dictating. Starts as a one-line pill and grows upward as you
/// talk, up to a few lines; beyond that the oldest lines scroll off the top so the newest
/// words stay visible.
///
/// The panel must never become key: if it took focus, the user's text field would lose it
/// and the paste would land nowhere.
@MainActor
final class HUDController {
    private let panel: NSPanel

    init(dictation: Dictation) {
        panel = Self.makePanel(dictation: dictation)
        observe(dictation)
    }

    /// The exact shipping panel, so performance fixtures measure what the user sees.
    static func makePanel(dictation: Dictation, reduceMotion: Bool? = nil) -> NSPanel {
        let panel = HUDPanel(
            // Transparent and click-through, so it's sized for the tallest state; the bar
            // itself sits at the bottom and grows into the empty space.
            contentRect: NSRect(x: 0, y: 0, width: HUDView.width + 40, height: HUDView.maxHeight + 40),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = dictation.correctionPrompt == nil
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: HUDView(dictation: dictation, reduceMotion: reduceMotion))
        // The panel never resizes, so skip AppKit's min/ideal/max sizing queries: each one
        // re-laid-out the whole transcript on every partial result.
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private func observe(_ dictation: Dictation) {
        withObservationTracking {
            _ = dictation.phase
            _ = dictation.correctionPrompt
            _ = dictation.correctionAdded
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.panel.ignoresMouseEvents = dictation.correctionPrompt == nil
                self.update(visible: dictation.phase != .idle || dictation.correctionPrompt != nil || dictation.correctionAdded)
                self.observe(dictation)
            }
        }
    }

    private func update(visible: Bool) {
        if visible {
            guard !panel.isVisible else { return }
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 28))
            }
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }
}

struct HUDView: View {
    static let width: CGFloat = 460
    static let maxTextHeight: CGFloat = 104 // ~5 lines
    static let maxHeight: CGFloat = maxTextHeight + 80 // + chip row, hint line, padding

    let dictation: Dictation
    var reduceMotion: Bool?
    /// Natural height of the full text, measured, so the bar can hug it until it overflows.
    @State private var textHeight: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let pair = dictation.correctionPrompt {
                CorrectionPrompt(pair: pair, add: dictation.addCorrection, notNow: dictation.dismissCorrection)
            } else if dictation.correctionAdded {
                Text("Added to Dictionary").font(Brand.Font.hud).foregroundStyle(Brand.textOnNavy)
            } else {
                WaveBars(level: dictation.level, active: dictation.phase == .listening)
                    .frame(width: 46, height: 28)
                VStack(alignment: .leading, spacing: 6) {
                    if !dictation.modes.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(dictation.modes, id: \.self) { ModeChip($0) }
                        }
                    }
                    // DESIGN: First-use Apple speech preparation uses a native progress indicator.
                    if dictation.phase == .starting, let progress = dictation.assetProgress {
                        ProgressView("Preparing…", value: progress).tint(Brand.sky)
                    } else if let busy = dictation.busyLabel {
                        ShimmerText(busy)
                    } else {
                        transcript
                    }
                    if let hint = dictation.hint {
                        Text(hint).font(Brand.Font.hint).foregroundStyle(Brand.secondaryOnNavy)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: Self.width)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: Brand.Radius.hud, style: .continuous)
                .fill(Brand.navy.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.hud, style: .continuous).strokeBorder(.white.opacity(0.1)))
        )
        .animation(.easeOut(duration: 0.15), value: dictation.modes)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
        .environment(\.colorScheme, .dark)
    }

    private var transcript: some View {
        let observedHeightLimit = Self.maxTextHeight + 1
        return RevealText(label, volatileTail: dictation.volatileText, reduceMotion: reduceMotion,
                          visibleHeight: Self.maxTextHeight)
            .font(Brand.Font.hud)
            .foregroundStyle(isError ? Brand.error : Brand.textOnNavy)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { min($0.size.height, observedHeightLimit) } action: { textHeight = $0 }
            // Bottom-aligned and clipped: once the text outgrows the bar, the newest
            // lines stay in view and older ones slide off the top.
            .frame(height: min(textHeight, Self.maxTextHeight), alignment: .bottom)
            .clipped()
            .mask(fade)
    }

    /// Once text overflows, fade the top edge so lines scrolling off read as continuing,
    /// not cut.
    private var fade: LinearGradient {
        let overflowing = textHeight > Self.maxTextHeight
        return LinearGradient(
            stops: [.init(color: overflowing ? .clear : .black, location: 0), .init(color: .black, location: 0.22)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var isError: Bool {
        if case .failed = dictation.phase { return true }
        return false
    }

    private var label: String {
        switch dictation.phase {
        case .idle, .starting: dictation.listeningPlaceholder
        case .listening: dictation.liveText.isEmpty ? dictation.listeningPlaceholder : dictation.liveText
        case .finishing: dictation.liveText.isEmpty ? "Finishing…" : dictation.liveText
        case .rewriting: dictation.busyLabel ?? "Refining…"
        case .failed(let message): message
        }
    }
}

/// Clickable correction buttons must leave the host field as the keyboard target.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
