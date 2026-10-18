import SwiftUI

/// Clock-driven so replacing a keyboard's hosting root never freezes the working indicator.
public struct BusyRing: View {
    private let lineWidth: CGFloat
    public init(lineWidth: CGFloat = 2) { self.lineWidth = lineWidth }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Circle().trim(from: 0, to: 0.7)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .padding(lineWidth / 2)
                .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1) * 360))
        }
        .accessibilityHidden(true)
    }
}

/// Shared Talk control artwork; the caller owns the button action and busy interaction.
public struct TalkButton: View {
    public enum State: Equatable { case idle, starting, listening(Float), finishing(Bool) }
    let state: State
    let height: CGFloat
    let idleLabel: String

    public init(state: State, height: CGFloat = 52, idleLabel: String = "Talk") {
        self.state = state
        self.height = height
        self.idleLabel = idleLabel
    }

    public var body: some View {
        HStack(spacing: 10) {
            if isBusy { BusyRing().frame(width: 22, height: 22) }
            else { TrioMark(level: level).frame(width: 26, height: 26) }
            Text(label).font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Brand.navy, in: Capsule())
        .overlay {
            if level != nil {
                Capsule().strokeBorder(LinearGradient(colors: [Brand.sky, Brand.amber, Brand.coral],
                    startPoint: .leading, endPoint: .trailing), lineWidth: 2)
            } else { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1.5) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch state {
        case .idle: idleLabel
        case .starting: "Opening Scribe…"
        case .listening: "Done"
        case .finishing(let refine): refine ? "Refining…" : "Finishing…"
        }
    }
    private var isBusy: Bool {
        switch state { case .starting, .finishing: true; default: false }
    }
    private var level: Float? {
        if case .listening(let level) = state { return level }
        return nil
    }
}
