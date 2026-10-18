import SwiftUI

/// The app and editor use the same flat controls as the keyboard, without a gradient stroke.
public struct RefinePill: View {
    public let isOn: Bool
    public init(isOn: Bool) { self.isOn = isOn }
    public var body: some View {
        HStack(spacing: 6) {
            RefineGlyph().frame(width: 16, height: 16)
            Text("Refine")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(isOn ? Brand.navy : Color.primary.opacity(0.7))
        .padding(.horizontal, 12).frame(height: 32)
        .background(isOn ? Brand.amber : Color.primary.opacity(0.12), in: Capsule())
    }
}

public struct ToneChip: View {
    public let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title).font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 8).frame(height: 32)
            .background(Color.primary.opacity(0.12), in: Capsule())
    }
}

public struct RefinePresetChip: View {
    public let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title).font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14).frame(height: 34)
            .background(Color.primary.opacity(0.12), in: Capsule())
    }
}
