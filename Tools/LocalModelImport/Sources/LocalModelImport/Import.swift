import Foundation
import OfflineCore

/// Explicit local installation utility. Uses the same checksum and receipt code as the app.
@main struct LocalModelImport {
    struct Item: Decodable { let source: URL; let model: ModelDescriptor; let package: ModelPackage? }
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: LocalModelImport plan.json application-support-directory") }
        let items = try JSONDecoder().decode([Item].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let store = ModelStore(root: root.appendingPathComponent("Models"))
        let packages = PackageStore(root: root.appendingPathComponent("VoicePackages"))
        let staging = root.appendingPathComponent("LocalImport-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for item in items {
            let installed: URL
            if let existing = try await store.installedURL(for: item.model) { installed = existing }
            else {
                let copy = staging.appendingPathComponent(item.model.id)
                try FileManager.default.copyItem(at: item.source, to: copy)
                installed = try await store.verifyAndInstall(stagingURL: copy, model: item.model)
            }
            if let package = item.package, try await packages.readyDirectory(for: package) == nil {
                _ = try await packages.install(archive: installed, package: package)
            }
            print("Verified and installed: \(item.model.id)")
        }
    }
}
