import Foundation
import Combine
import OfflineCore

@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader(model: .turbo)
    #if os(iOS)
    // Reconnect on an old background-session callback only; do not start new F16 downloads.
    static let legacyWhisper = ModelDownloader(model: SharedModelAssets.turboDefault)
    #endif
    nonisolated static let sessionID = "org.openoffline.translator.models.v1"
    nonisolated static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OfflineTranslator", isDirectory: true)
    static var backgroundCompletions: [String: () -> Void] = [:]
    nonisolated let transferRoot: URL
    nonisolated let identifier: String
    let model: ModelDescriptor
    let store: ModelStore
    @Published private(set) var state = TransferState(expectedBytes: ModelDescriptor.turbo.byteCount)
    @Published private(set) var installedURL: URL?
    @Published private(set) var isManaging = false
    @Published private(set) var restored = false
    @Published private(set) var allowCellular = false
    private var cellularObserver: AnyCancellable?
    private var taskAllowsCellular: Bool?
    private var currentTask: URLSessionDownloadTask?
    private var verification: Task<Void, Never>?
    private var verificationGeneration: Int?
    private var storedTaskID: Int?
    private var lastPersist = Date.distantPast
    private var session: URLSession!
    private var restoreStarted = false
    private var recordURL: URL { transferRoot.appendingPathComponent("transfer.json") }
    private var resumeURL: URL { transferRoot.appendingPathComponent("resume.data") }
    private struct Record: Codable {
        var state: TransferState
        var taskID: Int?
        var allowCellular: Bool
        var taskAllowsCellular: Bool?
    }
    init(model: ModelDescriptor) {
        self.model = model
        transferRoot = model.transferStorageKey.map { Self.root.appendingPathComponent("Downloads/" + $0) } ?? Self.root
        identifier = model.transferStorageKey.map { Self.sessionID + "." + $0 } ?? Self.sessionID
        store = ModelStore(root: Self.root.appendingPathComponent("Models", isDirectory: true), onUncachedVerification: ModelVerificationStatus.changed)
        super.init()
        state = TransferState(expectedBytes: model.byteCount)
        do {
            try Self.prepareTransferRoot(transferRoot, dataRoot: Self.root)
            if let data = try? Data(contentsOf: recordURL), let record = try? JSONDecoder().decode(Record.self, from: data) {
                state = record.state; storedTaskID = record.taskID; taskAllowsCellular = record.taskAllowsCellular
            }
        } catch { state.fail(error.localizedDescription, generation: state.generation) }
        allowCellular = DownloadAccessSettings.shared.allowCellular
        cellularObserver = DownloadAccessSettings.shared.$allowCellular.dropFirst().sink { [weak self] value in self?.allowCellular = value }
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 7 * 24 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    private func persist() {
        do {
            try JSONEncoder().encode(Record(state: state, taskID: storedTaskID, allowCellular: allowCellular, taskAllowsCellular: taskAllowsCellular))
                .write(to: recordURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Keep the active session usable; expose that restoration cannot be guaranteed.
            state.error = L10n.text("Не удалось сохранить состояние загрузки: \(error.localizedDescription)")
        }
        lastPersist = Date()
        DownloadLiveActivity.changed()
    }
    nonisolated private func stagingURL(generation: Int) -> URL {
        transferRoot.appendingPathComponent("staging-\(generation).bin")
    }
    /// The legacy Whisper transfer folder is the data root itself, which also holds History. Excluding it
    /// removed history from backups (always on the Mac); exclude only per-model transfer folders and undo the
    /// old root exclusion. Model and package stores exclude their own folders (audit 22.10, iOS M8).
    nonisolated static func prepareTransferRoot(_ transferRoot: URL, dataRoot: URL) throws {
        try FileManager.default.createDirectory(at: transferRoot, withIntermediateDirectories: true)
        let exclude = transferRoot.standardizedFileURL.path != dataRoot.standardizedFileURL.path
        // A fresh URL: a cached value on a reused URL object can make the write a no-op.
        var folder = URL(fileURLWithPath: transferRoot.path, isDirectory: true); var values = URLResourceValues()
        values.isExcludedFromBackup = exclude
        try folder.setResourceValues(values)
        if !exclude { removexattr(transferRoot.path, backupExclusionAttribute, 0) }
    }
    nonisolated static let backupExclusionAttribute = "com.apple.metadata:com_apple_backup_excludeItem"
    /// Staged downloads of earlier generations are orphans once their generation is gone.
    private func removeOrphanedStaging() {
        let current = stagingURL(generation: state.generation).lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: transferRoot.path)) ?? []
        for name in names where name.hasPrefix("staging-") && name.hasSuffix(".bin") && name != current {
            try? FileManager.default.removeItem(at: transferRoot.appendingPathComponent(name))
        }
    }
    func restore() async {
        guard !restoreStarted else { return }; restoreStarted = true
        let tasks = await session.allTasks
        for task in tasks {
            if task.taskIdentifier == storedTaskID, Int(task.taskDescription ?? "") == state.generation,
               state.phase == .downloading, let download = task as? URLSessionDownloadTask {
                currentTask = download; download.resume()
            } else { task.cancel() }
        }
        removeOrphanedStaging()
        // Delegate delivery can begin verification while allTasks is suspended.
        if verificationGeneration == state.generation { restored = true; return }
        if currentTask != nil { restored = true; return }
        let staged = self.stagingURL(generation: state.generation)
        if FileManager.default.fileExists(atPath: staged.path), [.checking, .downloading].contains(state.phase) {
            state.phase = .checking; restored = true
            verify(staged, generation: state.generation); return
        }
        isManaging = true
        do {
            installedURL = try await store.installedURL(for: model)
            if installedURL != nil { state.phase = .installed; state.error = nil }
            else if [.downloading, .checking, .installed].contains(state.phase) {
                state.phase = FileManager.default.fileExists(atPath: resumeURL.path) ? .paused : .restartRequired
            }
        } catch { state.fail(error.localizedDescription, generation: state.generation) }
        isManaging = false; restored = true; persist()
    }
    private func checkSpace() throws {
        let available = try transferRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        let required = model.byteCount * 2 + 256 * 1024 * 1024
        if let available, available < required {
            throw NSError(domain: "ModelDownload", code: 1, userInfo: [NSLocalizedDescriptionKey:
                L10n.text("Нужно \(L10n.bytes(required)) свободного места; доступно \(L10n.bytes(Int64(available))).")])
        }
    }
    func start(resuming: Bool = false) {
        guard restored, !isManaging, installedURL == nil, ![.downloading, .checking].contains(state.phase) else { return }
        do {
            try checkSpace()
            var resume: Data?
            // Resume data embeds the old URLRequest. Recreate it if permission changed;
            // otherwise enabling cellular would leave the old Wi-Fi-only request waiting.
            if resuming && DownloadAccessItem.canResume(previousCellular: taskAllowsCellular, allowCellular: allowCellular) {
                resume = try? Data(contentsOf: resumeURL)
                guard resume != nil else { state.phase = .restartRequired; persist(); return }
            }
            state.start(resuming: resume != nil)
            let task: URLSessionDownloadTask
            if let resume { task = session.downloadTask(withResumeData: resume) }
            else {
                try? FileManager.default.removeItem(at: resumeURL)
                var request = URLRequest(url: model.remoteURL)
                request.allowsCellularAccess = allowCellular
                request.allowsExpensiveNetworkAccess = allowCellular
                task = session.downloadTask(with: request)
            }
            taskAllowsCellular = allowCellular
            task.taskDescription = String(state.generation)
            currentTask = task; storedTaskID = task.taskIdentifier
            if TranslationModel(rawValue: model.id) != nil || model.id == ModelDescriptor.turbo.id { DownloadNotifications.started(model.id) }
            DownloadLiveActivity.started(model.id)
            persist(); task.resume()
        } catch { state.fail(error.localizedDescription, generation: state.generation); persist() }
    }
    func pause() async {
        guard !isManaging, state.phase == .downloading, let task = currentTask else { return }
        isManaging = true
        let generation = state.generation
        state.pause(hasResumeData: false, generation: generation)
        let data: Data? = await withCheckedContinuation { continuation in
            task.cancel { data in continuation.resume(returning: data) }
        }
        if generation == state.generation {
            do {
                if let data {
                    try data.write(to: resumeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    state.phase = .paused
                } else { state.phase = .restartRequired }
            } catch { state.fail(error.localizedDescription, generation: generation) }
            currentTask = nil; storedTaskID = nil; persist()
        }
        isManaging = false
    }
    func cancel() async {
        guard !isManaging else { return }
        isManaging = true
        let old = state.generation
        state.cancel(); persist()
        if currentTask == nil, let resume = try? Data(contentsOf: resumeURL) {
            // Resume data owns a system-managed partial file. Give it back to
            // URLSession for cancellation; deleting only the receipt leaks it.
            // Never start the task, and ignore its callbacks via the old generation.
            let abandoned = session.downloadTask(withResumeData: resume)
            abandoned.taskDescription = String(old)
            abandoned.cancel()
        }
        currentTask?.cancel(); currentTask = nil; storedTaskID = nil
        let pending = verification; pending?.cancel(); await pending?.value; verification = nil
        try? FileManager.default.removeItem(at: resumeURL)
        try? FileManager.default.removeItem(at: self.stagingURL(generation: old))
        // Installation may have finished just before cancellation. Drain verification before removing.
        if installedURL == nil { try? await store.remove(model) }
        isManaging = false; persist()
    }
    func clearInstalledReference() async {
        installedURL = nil; state.cancel(); persist()
    }
    func remove() async {
        guard !isManaging, state.phase == .installed else { return }
        isManaging = true
        do { try await store.remove(model); installedURL = nil; state.cancel() }
        catch { state.error = error.localizedDescription }
        isManaging = false; persist()
    }
    func importFile(_ url: URL) async {
        guard restored, !isManaging, installedURL == nil, ![.downloading, .checking].contains(state.phase) else { return }
        isManaging = true
        state.start(); state.phase = .checking; persist()
        let generation = state.generation
        let staging = self.stagingURL(generation: generation)
        do {
            try checkSpace()
            try await Task.detached {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: url, to: staging)
            }.value
            isManaging = false; verify(staging, generation: generation)
        } catch { isManaging = false; state.fail(error.localizedDescription, generation: generation); persist() }
    }
    private func verify(_ url: URL, generation: Int) {
        guard generation == state.generation else { try? FileManager.default.removeItem(at: url); return }
        guard verificationGeneration != generation else { return }
        verificationGeneration = generation
        state.phase = .checking; currentTask = nil; storedTaskID = nil; persist()
        verification = Task {
            let background = DownloadBackgroundWork()
            defer {
                background.end()
                if verificationGeneration == generation {
                    verificationGeneration = nil; verification = nil
                }
            }
            do {
                let installed = try await store.verifyAndInstall(stagingURL: url, model: model)
                guard generation == state.generation, !Task.isCancelled else { return }
                installedURL = installed; state.verified(generation: generation)
                if TranslationModel(rawValue: model.id) != nil || model.id == ModelDescriptor.turbo.id {
                    await DownloadNotifications.ready(model.id, title: model.title)
                }
                try? FileManager.default.removeItem(at: resumeURL)
            } catch {
                try? FileManager.default.removeItem(at: url)
                guard generation == state.generation else { return }
                state.fail(error.localizedDescription, generation: generation)
            }
            persist()
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let generation = Int(downloadTask.taskDescription ?? "") ?? -1
        Task { @MainActor in
            self.state.receive(totalBytesWritten, generation: generation)
            if Date().timeIntervalSince(self.lastPersist) > 2 { self.persist() }
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let generation = Int(downloadTask.taskDescription ?? "") ?? -1
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            Task { @MainActor in self.handleFailure(L10n.text("Сервер вернул HTTP \(status). Попробуйте позже."), generation: generation) }
            return
        }
        let staging = self.stagingURL(generation: generation)
        do {
            // URLSession removes location after this callback; transfer ownership synchronously.
            if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
            try FileManager.default.moveItem(at: location, to: staging)
            var file = staging; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? file.setResourceValues(values) // the legacy transfer folder itself is backed up
            Task { @MainActor in
                guard generation == self.state.generation else {
                    try? FileManager.default.removeItem(at: staging); return
                }
                // Paused or cancelled at the moment of completion: nothing will verify this file later.
                guard self.state.phase == .downloading else { try? FileManager.default.removeItem(at: staging); return }
                self.state.finished(generation: generation); self.verify(staging, generation: generation)
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in self.handleFailure(message, generation: generation) }
        }
    }
    private func handleFailure(_ message: String, generation: Int) {
        guard generation == state.generation, state.phase == .downloading else { return }
        currentTask = nil; storedTaskID = nil
        state.fail(message, generation: generation); persist()
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error as NSError? else { return }
        let generation = Int(task.taskDescription ?? "") ?? -1
        let resume = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            guard generation == self.state.generation, self.state.phase == .downloading else { return }
            self.currentTask = nil; self.storedTaskID = nil
            if let resume {
                do {
                    try resume.write(to: self.resumeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    self.state.pause(hasResumeData: true, generation: generation)
                    self.state.error = L10n.text("Загрузка прервана. Можно продолжить.")
                } catch { self.state.fail(error.localizedDescription, generation: generation) }
            } else {
                self.state.phase = .restartRequired
                self.state.error = L10n.text("Не удалось продолжить загрузку: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: self.resumeURL)
            }
            self.persist()
        }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            // The temporary file is moved synchronously by didFinishDownloadingTo.
            // Start validation here too in case its MainActor callback has not run yet.
            let staging = self.stagingURL(generation: self.state.generation)
            if FileManager.default.fileExists(atPath: staging.path), [.downloading, .checking].contains(self.state.phase) {
                self.verify(staging, generation: self.state.generation)
            }
            await self.verification?.value
            await PackageDownloadCoordinator.shared.finishBackgroundDownload(self)
            self.persist()
            // Do not relinquish background runtime with a publication still
            // sleeping in the Live Activity throttle.
            await DownloadLiveActivity.flush()
            let completion = Self.backgroundCompletions.removeValue(forKey: self.identifier)
            completion?()
        }
    }
}
