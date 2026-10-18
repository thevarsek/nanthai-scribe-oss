import AppKit
import ScribeUI

/// Menu bar glyph: the app icon's three planes (white, gradient ribbon, coral) at 18 pt.
///
/// Drawn rather than an SF Symbol because symbols render as monochrome templates.
/// Idle is dimmed so the bar doesn't shout; while listening it's fully lit.
@MainActor
enum MenuBarIcon {
    static let idle = make(alpha: 0.75)
    static let listening = make(alpha: 1)

    static let recording = make(alpha: 0.75, recording: true)
    static let recordingListening = make(alpha: 1, recording: true)
    static func image(listening: Bool, recording: Bool) -> NSImage {
        recording ? (listening ? recordingListening : self.recording) : (listening ? self.listening : idle)
    }

    /// Bar corners in an 18 pt box, y down (matches Tools/MakeIcon.swift scaled down).
    private static let planes: [[CGPoint]] = [
        [CGPoint(x: 3, y: 6.84), CGPoint(x: 5.2, y: 4.99), CGPoint(x: 5.2, y: 11.16), CGPoint(x: 3, y: 13.01)],
        [CGPoint(x: 7.9, y: 3.09), CGPoint(x: 10.1, y: 1.24), CGPoint(x: 10.1, y: 14.91), CGPoint(x: 7.9, y: 16.76)],
        [CGPoint(x: 12.8, y: 5.34), CGPoint(x: 15, y: 3.49), CGPoint(x: 15, y: 12.66), CGPoint(x: 12.8, y: 14.51)],
    ]

    private static func make(alpha: CGFloat, recording: Bool = false) -> NSImage {
        let size = NSSize(width: recording ? 22 : 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            func color(_ hex: UInt32) -> NSColor {
                NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
            }
            let ribbon = NSGradient(colors: [0x1EC8FF, 0x5EE0F6, 0xCFEEAE, 0xFFD94A, 0xFFA51F].map(color),
                                    atLocations: [0, 0.38, 0.53, 0.65, 1], colorSpace: .sRGB)!
            for (i, corners) in planes.enumerated() {
                let path = NSBezierPath()
                path.move(to: corners[0])
                corners.dropFirst().forEach(path.line(to:))
                path.close()
                path.lineWidth = 1.4
                path.lineJoinStyle = .round
                if i == 1 {
                    // Gradient fill can't stroke, so fatten the ribbon by clipping to its outline.
                    NSGraphicsContext.saveGraphicsState()
                    let outline = path.cgPath.copy(strokingWithWidth: 1.4, lineCap: .round, lineJoin: .round, miterLimit: 10)
                        .union(path.cgPath)
                    NSGraphicsContext.current?.cgContext.addPath(outline)
                    NSGraphicsContext.current?.cgContext.clip()
                    ribbon.draw(from: NSPoint(x: 7.2, y: 17), to: NSPoint(x: 10.8, y: 1), options: [])
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    // The white plane follows the menu bar's label colour so it shows on light bars too.
                    let fill = i == 0 ? NSColor.labelColor.withAlphaComponent(alpha) : color(0xFF5A4A)
                    fill.setFill(); fill.setStroke()
                    path.fill(); path.stroke()
                }
            }
            if recording {
                NSColor(Brand.coral).setFill()
                NSBezierPath(ovalIn: NSRect(x: 17, y: 0, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
