import Foundation
import Combine
import OfflineCore

struct RecognitionPackage: Decodable, Identifiable {
    let id: String, title: String, license: String, developmentFolder: String
    let sourceURL: URL
    let parts: [VoicePackagePart]
    var manifest: ModelPackage { ModelPackage(id: id, archiveRoot: id, files: parts.map { PackageFile(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256) }) }
}

/// Multi-file CoreML packages use the same verified, resumable downloads as other models.
@MainActor final class RecognitionPackages: ObservableObject {
    static let definitions: [RecognitionPackage] = {
        guard let url = Bundle.main.url(forResource: "recognition-packages", withExtension: "json"),
              let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([RecognitionPackage].self, from: data) else {
            preconditionFailure("Invalid recognition package catalog")
        }
        return list
    }()
    let downloaders: [ModelDownloader]
    @Published private(set) var directories: [String: URL] = [:]
    @Published private(set) var busyID: String?
    @Published private(set) var errors: [String: String] = [:]
    private let store = PackageStore(root: ModelDownloader.root.appendingPathComponent("RecognitionPackages", isDirectory: true), onUncachedVerification: ModelVerificationStatus.changed)
    private var job: Task<Void, Never>?
    private var assemblies: [String: Task<URL, Error>] = [:]
    private var observers = Set<AnyCancellable>()
    private let pendingKey = "pendingRecognitionPackages"
    init() {
        downloaders = Self.definitions.flatMap { definition in definition.parts.map {
            ModelDownloader(model: ModelDescriptor(id: $0.id, title: definition.title, remoteURL: $0.remoteURL, byteCount: $0.byteCount, sha256: $0.sha256))
        } }
        for downloader in downloaders {
            downloader.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        }
    }
    func parts(_ definition: RecognitionPackage) -> [ModelDownloader] {
        definition.parts.compactMap { part in downloaders.first { $0.model.id == part.id } }
    }
    var ultra: URL? { directories[RecognitionCatalog.ultraID] }
    func restore() async {
        for definition in Self.definitions {
            do {
                if let ready = try await store.readyDirectory(for: definition.manifest) { directories[definition.id] = ready; continue }
                // Reuse the benchmark files already transferred by cable. Hashes are mandatory;
                // development paths never become inference paths and are never trusted by name.
                let staged = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("DevelopmentModels/" + definition.developmentFolder)
                if FileManager.default.fileExists(atPath: staged.path) {
                    directories[definition.id] = try await store.install(files: Dictionary(uniqueKeysWithValues: definition.parts.map { ($0.path, staged.appendingPathComponent($0.path)) }), package: definition.manifest)
                } else if parts(definition).allSatisfy({ $0.installedURL != nil }) {
                    try await assemble(definition)
                }
            } catch { errors[definition.id] = L10n.text("Не удалось проверить пакет распознавания. Скачайте его заново.") }
        }
        if let ids = UserDefaults.standard.stringArray(forKey: pendingKey) { start(ids: ids) }
    }
    private func assemble(_ definition: RecognitionPackage) async throws {
        if directories[definition.id] != nil { return }
        if let pending = assemblies[definition.id] { _ = try await pending.value; return }
        let items = parts(definition)
        guard items.allSatisfy({ $0.installedURL != nil }) else { throw PackageError.incomplete }
        let files = Dictionary(uniqueKeysWithValues: zip(definition.parts, items).map { ($0.0.path, $0.1.installedURL!) })
        let pending = Task { try await store.install(files: files, package: definition.manifest) }
        assemblies[definition.id] = pending
        let background = DownloadBackgroundWork()
        defer { assemblies[definition.id] = nil; background.end() }
        directories[definition.id] = try await pending.value
        DownloadLiveActivity.changed()
        await DownloadNotifications.ready(definition.id, title: definition.title)
    }

    func assembleCompletedPackages() async {
        for definition in Self.definitions where directories[definition.id] == nil && parts(definition).allSatisfy({ $0.installedURL != nil }) {
            do { try await assemble(definition) } catch { errors[definition.id] = error.localizedDescription }
        }
    }
    func start(ids: [String]) {
        guard job == nil else { return }
        UserDefaults.standard.set(ids, forKey: pendingKey)
        // Submit the entire set while foregrounded; iOS owns transfers after suspension.
        for definition in Self.definitions where ids.contains(definition.id) && directories[definition.id] == nil {
            DownloadNotifications.started(definition.id)
            for item in parts(definition) where item.installedURL == nil { item.start(resuming: item.state.phase == .paused) }
        }
        job = Task {
            defer { job = nil; busyID = nil; UserDefaults.standard.removeObject(forKey: pendingKey) }
            for definition in Self.definitions where ids.contains(definition.id) && directories[definition.id] == nil {
                busyID = definition.id; errors[definition.id] = nil
                do {
                    for item in parts(definition) {
                        try Task.checkCancellation()
                        if item.installedURL == nil {
                            item.start(resuming: item.state.phase == .paused)
                            while item.isManaging || [.downloading, .checking].contains(item.state.phase) {
                                try await Task.sleep(nanoseconds: 200_000_000)
                            }
                            guard item.installedURL != nil else { throw PackageError.incomplete }
                        }
                    }
                    try Task.checkCancellation(); try await assemble(definition)
                } catch is CancellationError { return }
                catch { errors[definition.id] = L10n.text("Не удалось скачать пакет распознавания. Можно продолжить загрузку."); return }
            }
        }
    }
    func waitForDownloads() async { await job?.value }
    func pause() async {
        job?.cancel(); await job?.value
        for item in downloaders where item.state.phase == .downloading { await item.pause() }
    }
    func remove(_ definition: RecognitionPackage) async {
        await pause()
        do {
            try await store.remove(definition.manifest)
            directories[definition.id] = nil
            for item in parts(definition) { await item.cancel(); try await item.store.remove(item.model); await item.clearInstalledReference() }
            // Prevent automatic re-import of a deliberately deleted package on the next launch.
            let staged = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DevelopmentModels/" + definition.developmentFolder)
            if FileManager.default.fileExists(atPath: staged.path) { try FileManager.default.removeItem(at: staged) }
        } catch { errors[definition.id] = error.localizedDescription }
    }
}
