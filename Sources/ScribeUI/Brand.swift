import SwiftUI

/// NanthAi Scribe design tokens. See docs/DESIGN.md — don't add colours outside this list.
public enum Brand {
    public static let white = Color(hex: 0xF2F4F7)
    public static let sky = Color(hex: 0x1EC8FF)
    /// The website's page ground; the darkest surface (Mac HUD).
    public static let ink = Color(hex: 0x0A0E14)
    public static let navy = Color(hex: 0x16212E)
    public static let navyRaised = Color(hex: 0x1F2D3D)
    public static let cyan = Color(hex: 0x26C6DA)
    public static let amber = Color(hex: 0xFFC235)
    public static let coral = Color(hex: 0xFF7A59)
    public static let textOnNavy = Color.white.opacity(0.9)
    public static let secondaryOnNavy = Color.white.opacity(0.55)
    public static let error = Color(hex: 0xFF8A80)

    public static let gradientStops: [Gradient.Stop] = [
        .init(color: cyan, location: 0), .init(color: amber, location: 0.55), .init(color: coral, location: 1),
    ]
    public static let gradient = LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing)
    public static let angularGradient = AngularGradient(
        stops: gradientStops + [.init(color: cyan, location: 1)], center: .center
    )

    public enum Font {
        public static let hud = SwiftUI.Font.system(size: 13, weight: .medium)
        public static let hint = SwiftUI.Font.system(size: 11)
        public static let chip = SwiftUI.Font.system(size: 11, weight: .semibold)
    }

    public enum Radius {
        public static let hud: CGFloat = 28
        public static let key: CGFloat = 10
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
