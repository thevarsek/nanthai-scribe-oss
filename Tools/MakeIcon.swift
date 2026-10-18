// Renders the NanthAi Scribe icon ("Trio"): the NanthAi monogram's three planes —
// white, gradient ribbon, coral — as three sheared waveform bars on navy.
// Usage: swift Tools/MakeIcon.swift <out-dir>
// Writes icon-mac-1024.png (macOS squircle with margin) and icon-ios-1024.png (full bleed).
import AppKit

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func gradient(_ stops: [(CGFloat, UInt32)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { rgb($0.1) } as CFArray,
               locations: stops.map(\.0))!
}

/// One bar: a parallelogram (SVG coordinates, y down), its gradient and gradient axis.
struct Plane {
    let points: [CGPoint]
    let gradient: CGGradient
    let from: CGPoint, to: CGPoint
}

// Stops sampled from the NanthAi monogram; extra stops keep blue→yellow from going grey-green.
let planes = [
    Plane(points: [CGPoint(x: 265, y: 426.12), CGPoint(x: 367, y: 340.54), CGPoint(x: 367, y: 597.88), CGPoint(x: 265, y: 683.46)],
          gradient: gradient([(0, 0xFFFFFF), (1, 0xE3E8EE)]), from: CGPoint(x: 241, y: 312), to: CGPoint(x: 391, y: 712)),
    Plane(points: [CGPoint(x: 461, y: 266.12), CGPoint(x: 563, y: 180.54), CGPoint(x: 563, y: 757.88), CGPoint(x: 461, y: 843.46)],
          gradient: gradient([(0, 0x1EC8FF), (0.24, 0x2CD2FF), (0.38, 0x5EE0F6), (0.47, 0x9FEADB), (0.53, 0xCFEEAE),
                              (0.58, 0xF0EB8C), (0.65, 0xFFD94A), (0.8, 0xFFC235), (1, 0xFFA51F)]),
          from: CGPoint(x: 437, y: 832), to: CGPoint(x: 587, y: 192)),
    Plane(points: [CGPoint(x: 657, y: 355.72), CGPoint(x: 759, y: 270.14), CGPoint(x: 759, y: 668.28), CGPoint(x: 657, y: 753.86)],
          gradient: gradient([(0, 0xFF7A3E), (0.35, 0xFF5F43), (1, 0xFF4B5C)]),
          from: CGPoint(x: 0, y: 262), to: CGPoint(x: 0, y: 762)),
]

func render(size: CGFloat, mac: Bool) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ns
    let cg = ns.cgContext

    // Work in SVG space: y down, 1024 units; macOS art sits in an 824pt squircle with a soft shadow.
    cg.translateBy(x: 0, y: size)
    cg.scaleBy(x: size / 1024, y: -size / 1024)
    if mac {
        cg.translateBy(x: 100, y: 100)
        cg.scaleBy(x: 824 / 1024, y: 824 / 1024)
    }
    let body = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                      cornerWidth: mac ? 230 : 0, cornerHeight: mac ? 230 : 0, transform: nil)
    if mac {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
        cg.addPath(body); cg.setFillColor(rgb(0x121923)); cg.fillPath()
        cg.restoreGState()
    }
    cg.saveGState()
    cg.addPath(body); cg.clip()
    cg.setFillColor(rgb(0x121923))
    cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    cg.restoreGState()

    for plane in planes {
        // Round the parallelogram's corners: fill the polygon plus a 48-unit round-joined stroke.
        let polygon = CGMutablePath()
        polygon.addLines(between: plane.points); polygon.closeSubpath()
        cg.saveGState()
        cg.addPath(polygon.copy(strokingWithWidth: 48, lineCap: .round, lineJoin: .round, miterLimit: 10).union(polygon))
        cg.clip()
        cg.drawLinearGradient(plane.gradient, start: plane.from, end: plane.to,
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(filePath: CommandLine.arguments.dropFirst().first ?? ".")
for (name, mac) in [("icon-mac-1024.png", true), ("icon-ios-1024.png", false)] {
    try! render(size: 1024, mac: mac).representation(using: .png, properties: [:])!
        .write(to: out.appending(path: name))
}
print("wrote icons to \(out.path)")
