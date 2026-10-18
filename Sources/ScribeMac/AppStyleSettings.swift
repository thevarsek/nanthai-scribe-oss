import AppKit
import Foundation
import Observation
import ScribeCore

/// A stored "default" choice follows future default-tone changes, even for bundled apps.
@MainActor
@Observable
final class AppStyleSettings {
    private let defaults: UserDefaults
    private(set) var choices: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(choices) {
                defaults.set(data, forKey: "appStyleOverrides")
            }
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        choices = defaults.data(forKey: "appStyleOverrides")
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    func choice(for bundleID: String) -> String {
        if let choice = choices[bundleID], choice == "default" || RewriteTone(rawValue: choice) != nil { return choice }
        return AppStyleResolver.bundledTone(for: bundleID)?.rawValue ?? "default"
    }

    func set(_ choice: String, for bundleID: String) { choices[bundleID] = choice }
    func reset(_ bundleID: String) { choices.removeValue(forKey: bundleID) }

    func overrides(defaultTone: RewriteTone) -> [String: RewriteTone] {
        choices.compactMapValues { $0 == "default" ? defaultTone : RewriteTone(rawValue: $0) }
    }
}

struct AppStyleApplication: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    var isBundled: Bool { AppStyleResolver.bundledTone(for: id) != nil }

    @MainActor
    init?(url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        self.id = id
        name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    @MainActor
    static func installed(addedIDs: [String]) -> [Self] {
        var ids = Set(AppStyleResolver.bundledRules.keys).union(addedIDs)
        // JetBrains uses product-specific IDs, including Toolbox and early-access builds.
        let roots = [URL(filePath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
        for root in roots {
            guard let apps = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in apps where url.pathExtension == "app" {
                if let id = Bundle(url: url)?.bundleIdentifier, id.hasPrefix("com.jetbrains.") { ids.insert(id) }
            }
        }
        return ids.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).flatMap(Self.init(url:))
        }.sorted {
            if $0.isBundled != $1.isBundled { return $0.isBundled }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
