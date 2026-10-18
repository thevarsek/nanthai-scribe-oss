import SwiftUI

/// The icon's three sheared bars, drawn in the original 18-point coordinate space.
public struct TrioMark: View {
    private let level: Float?

    public init(level: Float? = nil) { self.level = level }

    public var body: some View {
        Group {
            if level == nil {
                // Static marks also live in widget archives, where no animation timeline is needed.
                bars(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    bars(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func bars(at time: Double) -> some View {
        ZStack {
            bar(x: 3, top: 6.84, bottom: 13.01, scale: scale(0.35, 1, time, 0))
                .fill(Brand.white)
            bar(x: 7.9, top: 3.09, bottom: 16.76, scale: scale(0.55, 1.15, time, 1))
                .fill(LinearGradient(stops: [
                    .init(color: Brand.sky, location: 0),
                    .init(color: Color(hex: 0x5EE0F6), location: 0.45),
                    .init(color: Color(hex: 0xFFD94A), location: 0.6),
                    .init(color: Color(hex: 0xFFA51F), location: 1)
                ], startPoint: UnitPoint(x: 0.5, y: 16.76 / 18),
                   endPoint: UnitPoint(x: 0.5, y: 1.24 / 18)))
            bar(x: 12.8, top: 5.34, bottom: 14.51, scale: scale(0.45, 1.05, time, 2))
                .fill(Brand.coral)
        }
    }

    private func scale(_ low: CGFloat, _ high: CGFloat, _ time: Double, _ index: Double) -> CGFloat {
        guard let level else { return 1 }
        let lifted = CGFloat(max(0, min(1, level))).squareRoot()
        let wobble = CGFloat((sin(time * 9 + index * 1.7) + 1) / 2)
        return low + (high - low) * lifted * (0.8 + 0.2 * wobble)
    }

    private func bar(x: CGFloat, top: CGFloat, bottom: CGFloat, scale: CGFloat) -> ShearedBar {
        ShearedBar(x: x, top: top, bottom: bottom, scale: scale)
    }
}

private struct ShearedBar: Shape {
    let x: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    var scale: CGFloat

    func path(in rect: CGRect) -> Path {
        let centre = (top + bottom - 1.85) / 2
        let points = [CGPoint(x: x, y: top), CGPoint(x: x + 2.2, y: top - 1.85),
                      CGPoint(x: x + 2.2, y: bottom - 1.85), CGPoint(x: x, y: bottom)]
            .map { CGPoint(x: rect.minX + $0.x * rect.width / 18,
                           y: rect.minY + (centre + ($0.y - centre) * scale) * rect.height / 18) }
        var path = Path()
        // Rounded joins keep the tiny mark faithful at keyboard and Live Activity sizes.
        for index in points.indices {
            let previous = points[(index + 3) % 4]
            let point = points[index]
            let next = points[(index + 1) % 4]
            let radius = min(rect.width, rect.height) * 0.7 / 18
            func inset(toward other: CGPoint) -> CGPoint {
                let distance = hypot(other.x - point.x, other.y - point.y)
                let fraction = min(0.5, radius / max(distance, 0.001))
                return CGPoint(x: point.x + (other.x - point.x) * fraction,
                               y: point.y + (other.y - point.y) * fraction)
            }
            let entry = inset(toward: previous)
            if index == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
            path.addQuadCurve(to: inset(toward: next), control: point)
        }
        path.closeSubpath()
        return path
    }
}
