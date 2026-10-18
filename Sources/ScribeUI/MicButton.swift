import SwiftUI

/// Round mic control for the iOS app and keyboard: navy disc with a gradient ring.
public struct MicButton: View {
    public enum State: Equatable, Sendable { case idle, listening(level: Float), busy }

    let state: State
    let size: CGFloat

    public init(state: State, size: CGFloat = 72) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().fill(Brand.navy)
            ring
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(Brand.textOnNavy)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var ring: some View {
        let width = size * 0.045
        switch state {
        case .idle:
            Circle().strokeBorder(Brand.angularGradient, lineWidth: width)
        case .listening(let level):
            // Square root lifts normal speech (~0.5) to ~0.7 so the pulse is easy to see.
            let lifted = CGFloat(level).squareRoot()
            ZStack {
                Circle().fill(Brand.angularGradient).opacity(0.22 * lifted).blur(radius: size * 0.06)
                Circle().strokeBorder(Brand.angularGradient, lineWidth: width * (1 + lifted))
            }
            .padding(-lifted * size * 0.13)
            .opacity(0.65 + 0.35 * lifted)
            .animation(.easeOut(duration: 0.12), value: level)
        case .busy:
            BusyRing(lineWidth: width).foregroundStyle(Brand.angularGradient)
        }
    }

    private var symbol: String {
        switch state {
        case .idle: "mic.fill"
        case .listening: "checkmark"
        case .busy: "ellipsis"
        }
    }

    private var accessibilityText: String {
        switch state {
        case .idle: "Start dictation"
        case .listening: "Finish dictation"
        case .busy: "Working"
        }
    }
}
