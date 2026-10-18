import SwiftUI

/// The Refine mark everywhere (keyboard, iOS app, Mac). Owner chose `pencil.and.scribble`
/// on 2026-10-17: it reads as "rewrite this text" and is distinct from the Trio mark.
public struct RefineGlyph: View {
    public init() {}

    public var body: some View {
        Image(systemName: "pencil.and.scribble")
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .accessibilityHidden(true)
    }
}
