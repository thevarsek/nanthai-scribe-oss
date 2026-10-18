import SwiftUI

/// Dictation modes shown as chips on the HUD and keyboard.
public enum ScribeMode: Hashable, Sendable {
    case handsFree
    case polish
    case editSelection
    case translate(String)

    var symbol: String {
        switch self {
        case .handsFree: "lock.fill"
        case .polish: ""
        case .editSelection: "text.cursor"
        case .translate: "globe"
        }
    }

    var title: String {
        switch self {
        case .handsFree: "Hands-free"
        case .polish: "Refine"
        case .editSelection: "Edit selection"
        case .translate(let language): "→ \(language)"
        }
    }
}

/// Capsule label for an active mode: raised navy, hairline gradient stroke.
/// `isOn: false` renders the plain toggle state used by the keyboard's Refine chip.
public struct ModeChip: View {
    let mode: ScribeMode
    let isOn: Bool

    public init(_ mode: ScribeMode, isOn: Bool = true) {
        self.mode = mode
        self.isOn = isOn
    }

    public var body: some View {
        Label { Text(mode.title) } icon: {
            if mode == .polish { RefineGlyph().frame(width: 12, height: 12) }
            else { Image(systemName: mode.symbol) }
        }
            .labelStyle(ChipLabelStyle())
            .font(Brand.Font.chip)
            .foregroundStyle(isOn ? Brand.textOnNavy : Brand.secondaryOnNavy)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Brand.navyRaised))
            .overlay {
                Capsule().strokeBorder(isOn ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.white.opacity(0.08)), lineWidth: 1)
            }
            .fixedSize()
    }
}

private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
