import Foundation
import UIKit
import Combine
import Photos
import OfflineCore

@MainActor final class CameraModel: ObservableObject {
    let translation = ImageTranslationSession(backend: RoutedTranslationBackend())
    let packages: PackageDownloadCoordinator
    @Published var source: SpeechLanguage = .english
    @Published var target: SpeechLanguage = .russian
    @Published var automaticSource = false
    @Published private(set) var takingPhoto = false
    @Published var forceOpenOCR = false
    @Published private(set) var frozen: UIImage?
    @Published private(set) var overlay: UIImage?
    @Published private(set) var error: String?
    @Published private(set) var message: String?
    @Published private(set) var engine = ""
    @Published private(set) var recognizing = false
    @Published private(set) var active = false
    @Published private(set) var opening = false
    private let history: HistoryModel?
    private var archivedScene: Int?
    private var archiving: Task<Void, Never>?
    var hasResult: Bool { frozen != nil }
    private var frame: CGImage?
    private var anchor: [UInt8] = []
    private var ocrTask: Task<Void, Never>?
    private var startup: Task<Void, Never>?
    private var closing: Task<Void, Never>?
    private var generation = 0
    private var scene = 0
    private var lastOCR = 0.0
    private let ocr = HybridOCR()
    private let activation = CameraActivationGate()
    private var observers = Set<AnyCancellable>()
    private var orientation: CameraFrameOrientation = .portrait
    private var orientationRevision = 0
    private var overlayRevision = 0
    private var pendingOverlay: (blocks: [TranslatedImageBlock], size: CGSize, revision: Int, scene: Int)?
    private var overlayTask: Task<Void, Never>?
    lazy var capture = CameraCapture { [weak self] image, revision in await self?.receive(image, revision: revision) }
    func orient(_ value: CameraFrameOrientation) {
        guard value != orientation else { return }
        orientation = value; orientationRevision += 1
        capture.setOrientation(value, revision: orientationRevision)
        // Frozen/imported photos are already upright and must not be rotated a second time.
        guard frozen == nil else { return }
        scene += 1; ocrTask?.cancel(); translation.clearScene()
        frame = nil; overlay = nil; anchor = []; lastOCR = 0
    }
    func clearTextResult() {
        scene += 1; ocrTask?.cancel(); translation.clearScene(); overlay = nil; message = nil
    }
    init(packages: PackageDownloadCoordinator, history: HistoryModel? = nil) {
        self.packages = packages; self.history = history
        translation.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observers)
        translation.$complete.filter { $0 }.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.archiveResultIfNeeded() }
        }.store(in: &observers)
        translation.$translated.sink { [weak self] blocks in self?.scheduleOverlay(blocks) }.store(in: &observers)
    }
    /// A frame-sized raster with text fitting for every block took the main actor on each block update.
    /// Render off it, one at a time; only the newest blocks of the current scene are shown (audit 22.10, iOS C2).
    private func scheduleOverlay(_ blocks: [TranslatedImageBlock]) {
        guard let frame else { return }
        overlayRevision += 1
        guard !blocks.isEmpty else { overlay = nil; return }
        pendingOverlay = (blocks, CGSize(width: frame.width, height: frame.height), overlayRevision, scene)
        guard overlayTask == nil else { return }
        overlayTask = Task {
            while let job = pendingOverlay {
                pendingOverlay = nil
                let image = await Task.detached(priority: .userInitiated) { CameraOverlay.render(size: job.size, blocks: job.blocks) }.value
                if job.revision == overlayRevision && job.scene == scene { overlay = image }
            }
            overlayTask = nil
        }
    }
    var needsOpenModel: Bool { !automaticSource && ((forceOpenOCR && packages.ocr(source) != nil) || !HybridOCR.supports(source)) }
    var canSave: Bool { frozen != nil && translation.complete && !recognizing && error == nil && overlay != nil }
    var canCapture: Bool { active && frame != nil && frozen == nil && !takingPhoto }
    var status: String {
        if (!automaticSource && !packages.selectedTranslation.supports(source: source, target: target)) || !TranslationLanguage.details(target).connected(to: packages.selectedTranslation) { return PipelineError.modelLanguageUnavailable.localizedDescription }
        if opening { return L10n.text("Готовлю перевод с камеры…") }
        if takingPhoto { return L10n.text("Снимаю…") }
        if needsOpenModel && packages.ocr(source) == nil { return L10n.text("Распознавание этого языка камерой пока не подключено. Используйте текстовый режим.") }
        if needsOpenModel && packages.ocr(source)?.installedURL == nil { return L10n.text("Скачайте OCR-пакет в настройках распознавания") }
        if recognizing { return L10n.text("Распознаю текст…") }
        if translation.working { return L10n.text("Перевожу надписи…") }
        if translation.complete { return frozen == nil ? L10n.text("Перевод обновляется при изменении текста") : L10n.text("Перевод снимка готов") }
        return frozen == nil ? L10n.text("Наведите камеру на текст") : L10n.text("Текст не найден")
    }
    func open(modelURL: URL?) async {
        guard await activation.waitForClose(closing) else { return }
        guard !active, startup == nil else { return }
        guard let modelURL else { error = L10n.text("Сначала скачайте модель перевода в разделе «Модели»."); return }
        generation += 1; let id = generation; active = true; opening = true; error = nil; message = nil
        let task = Task {
            defer { opening = false; startup = nil }
            await translation.prepare(modelURL, model: packages.selectedTranslation)
            guard id == generation, !Task.isCancelled else { return }
            // A failed preparation keeps its error but leaves the camera inactive, so the shutter offers
            // "Start" again instead of staying disabled until the camera is closed (audit 22.10, iOS C4).
            guard translation.ready else { active = false; return }
            do { if frozen == nil { try await capture.start() }; if id != generation || Task.isCancelled { await capture.stop() } }
            catch { if id == generation { self.error = error.localizedDescription } }
        }
        startup = task; await task.value
    }
    private func receive(_ image: CGImage, revision: Int) {
        guard revision == orientationRevision, active, !opening, !takingPhoto, frozen == nil else { return }
        frame = image
        let signature = CameraOverlay.signature(image)
        if !anchor.isEmpty && CameraOverlay.distance(signature,anchor) > 0.025 { scene += 1; translation.clearScene(); overlay = nil; anchor = signature }
        guard ocrTask == nil, translation.ready, ProcessInfo.processInfo.systemUptime-lastOCR >= 0.8 else { return }
        if needsOpenModel && packages.ocr(source)?.installedURL == nil { return }
        recognize(image, signature: signature)
    }
    private func recognize(_ image: CGImage, signature: [UInt8]) {
        guard automaticSource || packages.selectedTranslation.supports(source: source, target: target), TranslationLanguage.details(target).connected(to: packages.selectedTranslation) else { error = PipelineError.modelLanguageUnavailable.localizedDescription; return }
        let id = generation, sceneID = scene, language = source, destination = target, automatic = automaticSource
        let force = !automatic && forceOpenOCR && packages.ocr(source) != nil, modelURL = automatic ? nil : packages.ocr(source)?.installedURL
        recognizing = true; error = nil; lastOCR = ProcessInfo.processInfo.systemUptime
        ocrTask = Task {
            defer { recognizing = false; ocrTask = nil }
            do {
                let result = try await ocr.recognize(image, source: automatic ? nil : language, forceOpen: force, modelURL: modelURL)
                try Task.checkCancellation()
                guard id == generation, sceneID == scene, active, automatic == automaticSource, (automatic || language == source), destination == target else { return }
                if frozen == nil, let latest = frame, CameraOverlay.distance(signature,CameraOverlay.signature(latest)) > 0.025 { return }
                anchor = signature; engine = result.engine
                if !result.blocks.isEmpty {
                    let resolved: SpeechLanguage
                    if automatic {
                        guard let detected = TextLanguageDetection.detect(result.blocks.map(\.text).joined(separator: "\n")) else { throw PipelineError.textNeedsLanguage }
                        resolved = detected; source = detected
                    } else { resolved = language }
                    guard packages.selectedTranslation.supports(source: resolved, target: destination) else { throw PipelineError.modelLanguageUnavailable }
                    translation.submit(result.blocks, source: resolved, target: destination)
                }
                if frozen != nil && result.blocks.isEmpty { error = CameraError.noText.localizedDescription }
            } catch is CancellationError {} catch { if id == generation && sceneID == scene { self.error = error.localizedDescription } }
        }
    }
    func takePicture() async {
        guard canCapture else { return }
        takingPhoto = true; let id = generation
        defer { takingPhoto = false }
        do {
            let image = try await capture.takePhoto()
            guard active, id == generation, !Task.isCancelled else { return }
            await usePicture(image)
        } catch { if id == generation { self.error = error.localizedDescription } }
    }
    func importData(_ data: Data) async {
        do {
            let image = try await Task.detached(priority: .userInitiated) { try CameraOverlay.decode(data) }.value
            guard active, !Task.isCancelled else { return }
            await usePicture(image)
        } catch { self.error = error.localizedDescription }
    }
    private func usePicture(_ image: CGImage) async {
        guard active else { return }
        scene += 1; let sceneID = scene; frozen = UIImage(cgImage: image); frame = image; overlay = nil; message = nil; translation.clearScene()
        ocrTask?.cancel(); await ocrTask?.value
        guard active, sceneID == scene else { return }
        await capture.stop()
        guard active, sceneID == scene else { return }
        recognize(image,signature:CameraOverlay.signature(image))
    }
    func changedOptions() async {
        scene += 1; let sceneID = scene; translation.clearScene(); overlay = nil; error = nil; message = nil; anchor = []
        ocrTask?.cancel(); await ocrTask?.value
        guard active, sceneID == scene else { return }
        if let frozen = frozen?.cgImage { recognize(frozen,signature:CameraOverlay.signature(frozen)) }
    }
    func resume() async {
        scene += 1; let sceneID = scene; ocrTask?.cancel(); await ocrTask?.value
        guard active, sceneID == scene else { return }
        frozen = nil; frame = nil; overlay = nil; error = nil; message = nil; anchor = []; translation.clearScene()
        do { try await capture.start(); if !active { await capture.stop() } } catch { self.error = error.localizedDescription }
    }
    private func archiveResultIfNeeded() {
        guard let history, frozen != nil, translation.complete, archivedScene != scene,
              let frame, let overlay, let png = CameraOverlay.composite(frame, overlay: overlay).pngData() else { return }
        let id = scene, blocks = translation.translated, source = source, target = target
        archivedScene = id
        archiving = Task {
            do { try await history.saveImage(png, blocks: blocks, source: source, target: target) }
            catch { if scene == id { self.error = error.localizedDescription } }
        }
    }
    func renderedPicture() throws -> UIImage {
        guard canSave, let frame, let overlay else { throw CameraError.image }
        return CameraOverlay.composite(frame,overlay:overlay)
    }
    func savePicture() async {
        do {
            let image = try renderedPicture()
            let permission = await PHPhotoLibrary.requestAuthorization(for:.addOnly)
            guard permission == .authorized || permission == .limited else { error = L10n.text("Разрешите добавление снимков в Фото в настройках iPhone."); return }
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            message = L10n.text("Картинка с переводом сохранена в Фото.")
        } catch { self.error = error.localizedDescription }
    }
    func sharePicture() throws -> URL {
        guard let data = try renderedPicture().pngData() else { throw CameraError.image }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Translated-"+UUID().uuidString+".png")
        try data.write(to:url,options:[.atomic,.completeFileProtection]); return url
    }
    func close() async {
        activation.invalidate()
        if let closing { await closing.value; return }
        archiveResultIfNeeded()
        let retained = archivedScene == scene
        active = false; generation += 1; scene += 1; if retained { archivedScene = scene }; startup?.cancel(); ocrTask?.cancel()
        let starting = startup, recognizing = ocrTask
        let task = Task {
            await translation.close(preservingResult: frozen != nil); await starting?.value; await recognizing?.value; await archiving?.value
            await capture.stop(); await ocr.unload()
            if frozen == nil { frame = nil; overlay = nil; anchor = [] }; closing = nil
        }
        closing = task; await task.value
    }
}
