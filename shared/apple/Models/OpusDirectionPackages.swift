import Foundation
import Combine
import OfflineCore

/// One OPUS-MT Big model direction (catalog shared with Android). Downloads, verification and
/// assembly mirror OpusPackage; files that are not hosted yet can be staged manually in
/// DevelopmentModels/<package id> and are installed after the same SHA-256 checks.
@MainActor final class OpusDirectionPackage: ObservableObject, Identifiable {
    let route: OpusDirectionRoute
    nonisolated var id: String { route.packageID }
    let downloaders: [ModelDownloader]
    @Published private(set) var directory: URL?
    @Published private(set) var installing = false
    @Published private(set) var error: String?
    private let store: PackageStore
    private var assembly: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()
    private var manifest: ModelPackage {
        ModelPackage(id: route.packageID, archiveRoot: route.packageID,
                     files: route.parts.map { PackageFile(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256) })
    }
    private var staged: URL {
        #if os(macOS)
        ModelDownloader.root.appendingPathComponent("DevelopmentModels/" + route.packageID)
        #else
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DevelopmentModels/" + route.packageID)
        #endif
    }
    init(route: OpusDirectionRoute, store: PackageStore) {
        self.route = route; self.store = store
        downloaders = route.parts.map { ModelDownloader(model: ModelDescriptor(id: $0.id, title: "OPUS " + route.direction,
            remoteURL: $0.remoteURL, byteCount: $0.byteCount, sha256: $0.sha256)) }
        for item in downloaders { item.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers) }
    }
    func contains(_ item: ModelDownloader) -> Bool { downloaders.contains { $0 === item } }
    var requirements: [DownloadRequirement] {
        downloaders.map { .init(id: $0.model.id, bytes: $0.model.byteCount, installed: directory != nil || $0.installedURL != nil) }
    }
    var downloading: Bool { downloaders.contains { [.downloading, .checking].contains($0.state.phase) || $0.isManaging } }
    func restore() async {
        do {
            if let ready = try await store.readyDirectory(for: manifest) { directory = ready; return }
            if FileManager.default.fileExists(atPath: staged.path) {
                installing = true; defer { installing = false }
                directory = try await store.install(files: Dictionary(uniqueKeysWithValues: route.parts.map { ($0.path, staged.appendingPathComponent($0.path)) }), package: manifest)
                try? FileManager.default.removeItem(at: staged)
            } else { await assembleIfComplete() }
        } catch { self.error = error.localizedDescription }
    }
    func assembleIfComplete() async {
        if let assembly { await assembly.value; return }
        guard directory == nil, downloaders.allSatisfy({ $0.installedURL != nil }) else { return }
        let files = Dictionary(uniqueKeysWithValues: zip(route.parts, downloaders).map { ($0.0.path, $0.1.installedURL!) })
        installing = true; error = nil
        let task = Task {
            // Like OpusPackage: keep background time for hashing and publish the finished state (audit 22.10, iOS M8).
            let background = DownloadBackgroundWork()
            defer { background.end(); installing = false; assembly = nil; DownloadLiveActivity.changed() }
            do { directory = try await store.install(files: files, package: manifest) }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
        assembly = task; await task.value
    }
    func start() {
        guard directory == nil, !installing, route.hosted else { return }
        error = nil
        for item in downloaders where item.installedURL == nil { item.start(resuming: item.state.phase == .paused) }
        Task { await assembleIfComplete() }
    }
    func pause() async { for item in downloaders where item.state.phase == .downloading { await item.pause() } }
    func cancel() async { assembly?.cancel(); await assembly?.value; for item in downloaders { await item.cancel() } }
    func discardAssembly() async throws {
        assembly?.cancel(); await assembly?.value
        try await store.remove(manifest); directory = nil; error = nil
    }
}

/// All direction packages; the same TranslationPackages store as the English OPUS package.
@MainActor final class OpusDirectionPackages: ObservableObject {
    let packages: [OpusDirectionPackage]
    private var observers = Set<AnyCancellable>()
    init() {
        let store = PackageStore(root: ModelDownloader.root.appendingPathComponent("TranslationPackages"),
                                 onUncachedVerification: { ModelVerificationStatus.changed($0) })
        packages = OpusDirectionRoutes.all.map { OpusDirectionPackage(route: $0, store: store) }
        for item in packages { item.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers) }
    }
    var downloaders: [ModelDownloader] { packages.flatMap(\.downloaders) }
    func package(containing item: ModelDownloader) -> OpusDirectionPackage? { packages.first { $0.contains(item) } }
    func package(_ id: String) -> OpusDirectionPackage? { packages.first { $0.id == id } }
    /// The installed package for a pair, following catalog priority.
    func installedRoute(_ source: String, _ target: String) -> OpusDirectionPackage? {
        guard let route = OpusDirectionRoutes.route(source, target, available: { self.package($0.packageID)?.directory != nil }), let package = package(route.packageID), package.directory != nil else { return nil }
        return package
    }
    /// Installed package directories by id, handed to the CTranslate2 backend.
    var directories: [String: URL] { Dictionary(uniqueKeysWithValues: packages.compactMap { p in p.directory.map { (p.id, $0) } }) }
    func restore() async { for item in packages { await item.restore() } }
}
