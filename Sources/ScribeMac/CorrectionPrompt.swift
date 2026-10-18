import ScribeCore
import ScribeUI
import SwiftUI

struct CorrectionPrompt: View {
    let pair: CorrectionPair
    let add: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Always spell “\(pair.heard)” as “\(pair.meant)”?")
                .font(.system(size: 13)).foregroundStyle(Brand.textOnNavy)
            HStack(spacing: 16) {
                Button("Add", action: add).foregroundStyle(Brand.coral)
                Button("Not now", action: notNow).foregroundStyle(Brand.secondaryOnNavy)
            }
            .buttonStyle(.borderless).font(.system(size: 13))
        }
    }
}
