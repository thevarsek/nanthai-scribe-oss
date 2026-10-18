import SwiftUI

/// Text with a slow brand-gradient sweep, for work-in-progress labels ("Refining…").
public struct ShimmerText: View {
    let text: String
    @State private var phase: CGFloat = -1

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(Brand.Font.hud)
            .foregroundStyle(Brand.textOnNavy.opacity(0.6))
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Brand.amber, location: 0.4),
                        .init(color: Brand.coral, location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 0.8, y: 0.5)
                )
                .mask(Text(text).font(Brand.Font.hud))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
    }
}
