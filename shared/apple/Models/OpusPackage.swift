import Foundation
import Combine
import OfflineCore

/// A single optional model choice contains both direct OPUS directions and their tokenizers.
@MainActor final class OpusPackage: ObservableObject {
    #if os(macOS)
    static let packageID = "opus-mt-big-gpu-fp16"
    private static let catalog = "opus-gpu-package"
    #else
    static let packageID = TranslationModel.opusBig.rawValue
    private static let catalog = "opus-package"
    #endif
    static let parts: [VoicePackagePart] = {
        guard let url = Bundle.main.url(forResource: catalog, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parts = try? JSONDecoder().decode([VoicePackagePart].self, from: data), !parts.isEmpty else {
            preconditionFailure("Invalid OPUS package manifest")
        }
        return parts
    }()
    static var bytes: Int64 { parts.reduce(0) { $0 + $1.byteCount } }
    static var manifest: ModelPackage {
        ModelPackage(id: packageID, archiveRoot: packageID,
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
        #if os(macOS)
        ModelDownloader.root.appendingPathComponent("DevelopmentModels/opus-gpu")
        #else
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DevelopmentModels/opus-big")
        #endif
    }
    init() {
        downloaders = Self.parts.map { ModelDownloader(model: ModelDescriptor(id: $0.id, title: "OPUS Big",
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
                await DownloadNotifications.ready(TranslationModel.opusBig.rawValue, title: "OPUS Big")
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
        assembly = task; await task.value
    }
    func start() {
        guard directory == nil, !installing else { return }
        error = nil
        DownloadNotifications.started(TranslationModel.opusBig.rawValue)
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
