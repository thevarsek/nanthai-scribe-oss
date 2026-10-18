import Foundation
import ScribeCore

@main struct DownloadModels {
    @MainActor static func main() async throws {
        #if os(macOS)
        let arguments = Array(CommandLine.arguments.dropFirst())
        let store: ModelStore
        if let index = arguments.firstIndex(of: "--root"), arguments.indices.contains(index + 1) {
            store = ModelStore(root: URL(filePath: arguments[index + 1], directoryHint: .isDirectory))
        } else { store = ModelStore() }
        let pauseAfter: Double? = arguments.firstIndex(of: "--pause-after").flatMap { index in
            arguments.indices.contains(index + 1) ? Double(arguments[index + 1]) : nil
        }
        for model in ModelCatalog.all where CommandLine.arguments.dropFirst().contains(model.id) {
            let start = ContinuousClock.now
            let reporting = Task { @MainActor in
                while !Task.isCancelled {
                    if let progress = store.progress[model.id] {
                        FileHandle.standardError.write(Data("\(model.id): \(progress.completedBytes)/\(progress.totalBytes) \(progress.status)\n".utf8))
                    }
                    try? await Task.sleep(for: .seconds(10))
                }
            }
            do {
                if let pauseAfter {
                    let download = Task { try await store.download(model) }
                    try await Task.sleep(for: .seconds(pauseAfter))
                    await store.pause(model)
                    _ = try? await download.value
                    print("Paused \(model.id): \(String(describing: store.progress[model.id]))")
                }
                try await store.download(model)
                reporting.cancel()
                print("\(model.id): \(model.expectedTotalSize) bytes in \(start.duration(to: .now)); \(store.directory(for: model).path)")
            } catch { reporting.cancel(); throw error }
        }
        #endif
    }
}
