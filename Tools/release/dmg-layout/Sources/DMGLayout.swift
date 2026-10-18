import DSStore
import Foundation

/// Finder's scripting server can block on mounted volumes. Write and read back its
/// metadata directly, with the background alias created against the mounted image.
@main
struct DMGLayout {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let path = arguments.last else { throw CocoaError(.fileReadInvalidFileName) }
        let mount = URL(filePath: path, directoryHint: .isDirectory)
        let storeURL = mount.appending(path: ".DS_Store")
        if arguments.first != "--verify" {
            var store = DSStore()
            store.setViewStyle(.icon)
            try store.setWindowBounds(top: 100, left: 100, bottom: 520, right: 740)
            store.setWindowSettings(.init(windowBounds: "{{100, 100}, {640, 420}}",
                containerShowSidebar: false, showSidebar: false, showTabView: false,
                showToolbar: false, showStatusBar: false, showPathBar: false, viewStyle: "icnv"))
            store.setIconViewSettings(.init(showIconPreview: true, showItemInfo: false,
                labelOnBottom: true, textSize: 13, iconSize: 104, gridSpacing: 100,
                viewOptionsVersion: 1, arrangeBy: "none"))
            try store.setIconPosition(for: "NanthAi Scribe.app", x: 180, y: 230)
            try store.setIconPosition(for: "Applications", x: 460, y: 230)
            try store.setBackgroundPicture(imageURL: mount.appending(path: ".background/background.tiff"), relativeTo: mount)
            try store.write(to: storeURL)
        }
        let readback = try DSStore.read(from: storeURL)
        guard readback.iconPosition(for: "NanthAi Scribe.app")?.x == 180,
              readback.iconPosition(for: "Applications")?.x == 460,
              readback.windowBounds()?.width == 640,
              readback.windowBounds()?.height == 420,
              readback.iconViewSettings()?.iconSize == 104,
              case .picture(let alias)? = readback.background(), !alias.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        print("DMG layout verified: 2 icons, background alias, 640×420 window.")
    }
}
