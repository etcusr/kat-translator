import Foundation
import Combine
import OfflineCore

/// Checked data-only Index weights and tokenizer for the packaged Mac MLX runtime.
@MainActor final class MacIndexPackage: ObservableObject {
    static let id = "index-translate-9b-mlx-mtp2"
    static let parts: [VoicePackagePart] = {
        guard let url = Bundle.main.url(forResource: "index-mlx-package", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parts = try? JSONDecoder().decode([VoicePackagePart].self, from: data), !parts.isEmpty else {
            preconditionFailure("Invalid Index MLX package manifest")
        }
        return parts
    }()
    static var bytes: Int64 { parts.reduce(0) { $0 + $1.byteCount } }
    static var manifest: ModelPackage {
        ModelPackage(id: Self.id, archiveRoot: Self.id,
            files: parts.map { PackageFile(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256) })
    }
    let downloaders: [ModelDownloader]
    @Published private(set) var directory: URL?
    @Published private(set) var installing = false
    @Published private(set) var error: String?
    private let store = PackageStore(root: ModelDownloader.root.appendingPathComponent("TranslationPackages"),
                                     onUncachedVerification: { ModelVerificationStatus.changed($0) })
    private var assembly: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()
    private var staged: URL {
        ModelDownloader.root.appendingPathComponent("DevelopmentModels/index-mlx")
    }
    init() {
        downloaders = Self.parts.map { ModelDownloader(model: ModelDescriptor(id: $0.id, title: "Index-Translate 9B · MLX + MTP2",
            remoteURL: $0.remoteURL, byteCount: $0.byteCount, sha256: $0.sha256)) }
        for item in downloaders {
            item.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        }
    }
    func contains(_ item: ModelDownloader) -> Bool { downloaders.contains { $0 === item } }
    var requirements: [DownloadRequirement] {
        downloaders.map { .init(id: $0.model.id, bytes: $0.model.byteCount, installed: directory != nil || $0.installedURL != nil) }
    }
    var progress: DownloadProgress {
        DownloadProgress(downloaders.map { .init(id: $0.model.id, expected: $0.model.byteCount,
            received: $0.state.receivedBytes, phase: $0.state.phase, ready: directory != nil, packageFailed: error != nil) })
    }
    var downloading: Bool { downloaders.contains { [.downloading, .checking].contains($0.state.phase) || $0.isManaging } }
    func restore() async {
        do {
            if let ready = try await store.readyDirectory(for: Self.manifest) { directory = ready; return }
            if FileManager.default.fileExists(atPath: staged.path) {
                installing = true; defer { installing = false }
                directory = try await store.install(files: Dictionary(uniqueKeysWithValues: Self.parts.map { ($0.path, staged.appendingPathComponent($0.path)) }), package: Self.manifest)
                // Staging is ours and only removed after the complete installed package passed verification.
                try? FileManager.default.removeItem(at: staged)
            } else { await assembleIfComplete() }
        } catch { self.error = error.localizedDescription }
    }
    func assembleIfComplete() async {
        if let assembly { await assembly.value; return }
        guard directory == nil, downloaders.allSatisfy({ $0.installedURL != nil }) else { return }
        let files = Dictionary(uniqueKeysWithValues: zip(Self.parts, downloaders).map { ($0.0.path, $0.1.installedURL!) })
        installing = true; error = nil
        let task = Task {
            let background = DownloadBackgroundWork()
            defer { background.end(); installing = false; assembly = nil; DownloadLiveActivity.changed() }
            do {
                directory = try await store.install(files: files, package: Self.manifest)
                await DownloadNotifications.ready(Self.id, title: "Index-Translate 9B · MLX + MTP2")
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
        assembly = task; await task.value
    }
    func start() {
        guard directory == nil, !installing else { return }
        error = nil
        DownloadNotifications.started(Self.id)
        for item in downloaders where item.installedURL == nil {
            item.start(resuming: item.state.phase == .paused)
        }
        Task { await assembleIfComplete() }
    }
    func pause() async {
        for item in downloaders where item.state.phase == .downloading { await item.pause() }
    }
    func cancel() async {
        assembly?.cancel(); await assembly?.value
        for item in downloaders { await item.cancel() }
    }
    func remove() async {
        await cancel()
        do {
            try await store.remove(Self.manifest); directory = nil
            for item in downloaders { try await item.store.remove(item.model); await item.clearInstalledReference() }
            if FileManager.default.fileExists(atPath: staged.path) { try FileManager.default.removeItem(at: staged) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
