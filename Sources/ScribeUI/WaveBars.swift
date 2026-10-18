import SwiftUI

/// Level-reactive waveform in the brand gradient. Flat when inactive.
public struct WaveBars: View {
    let level: Float
    let active: Bool
    let barCount: Int

    public init(level: Float, active: Bool, barCount: Int = 7) {
        self.level = level
        self.active = active
        self.barCount = barCount
    }

    /// Bars are 4 pt with 3 pt gaps; heights fill whatever height the caller gives.
    private static let barWidth: CGFloat = 4
    private static let gap: CGFloat = 3

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Square root lifts normal speech (~0.5) to ~0.7 so the bars move visibly.
            let lifted = CGFloat(level).squareRoot()
            // One gradient across the whole group (a gradient style applied to each bar
            // would resolve per bar and come out a single muddy colour).
            Rectangle()
                .fill(Brand.gradient)
                .mask {
                    GeometryReader { proxy in
                        let floor = Self.barWidth
                        HStack(spacing: Self.gap) {
                            ForEach(0..<barCount, id: \.self) { i in
                                let wobble = (sin(t * 9 + Double(i) * 1.7) + 1) / 2
                                Capsule()
                                    .frame(width: Self.barWidth,
                                           height: active ? floor + (proxy.size.height - floor) * lifted * (0.4 + 0.6 * wobble) : floor)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: CGFloat(barCount) * (Self.barWidth + Self.gap) - Self.gap)
        }
    }
}
