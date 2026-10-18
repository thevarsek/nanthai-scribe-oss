import AppKit
import SwiftUI

/// Compile alongside Sources/ScribeUI/{Brand,TrioMark}.swift to reuse the actual mark.
@main
struct MakeDMGBackground {
    @MainActor static func main() throws {
        let destination = URL(filePath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var representations: [NSBitmapImageRep] = []
        for scale in [1.0, 2.0] {
            let renderer = ImageRenderer(content:
                ZStack(alignment: .top) {
                    Brand.navy
                    TrioMark().frame(width: 96, height: 96).padding(.top, 24)
                }.frame(width: 640, height: 420)
            )
            renderer.scale = scale
            guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            bitmap.size = NSSize(width: 640, height: 420)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: destination.appending(path: scale == 1 ? "background.png" : "background@2x.png"))
            representations.append(bitmap)
        }
        guard let tiff = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try tiff.write(to: destination.appending(path: "background.tiff"))
    }
}
