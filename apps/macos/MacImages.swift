import SwiftUI
import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers
import OfflineCore

@MainActor final class CameraModel: ObservableObject {
    let translation: ImageTranslationSession
    let packages: PackageDownloadCoordinator
    @Published var source: SpeechLanguage = .english
    @Published var target: SpeechLanguage = .russian
    @Published var automaticSource = false
    @Published var image: NSImage?
    @Published var error: String?
    @Published var editedTranslation: String?
    var translatedText: String { editedTranslation ?? ImageTextLayout.plainText(translation.translated) }
    var displayedText: String { editedTranslation ?? ImageTextLayout.plainText(translation.displayedBlocks) }
    @Published private(set) var recognizing = false
    @Published private(set) var opening = false
    private let history: HistoryModel?
    private var subscriptions = Set<AnyCancellable>()
    private var archivedRevision: Int?
    private var archiving: Task<Void, Never>?
    var hasResult: Bool { image != nil }
    private var active = false
    private var pendingImport = false
    private var revision = 0
    private var job: Task<Void, Never>?
    private let ocr = HybridOCR()
    private var pixels: CGImage?
    private var modelURL: URL?
    private var translationModel: TranslationModel = .index9B
    private let beforePreparing: @MainActor () async -> Void
    private var closing: Task<Void, Never>?
    init(packages: PackageDownloadCoordinator, history: HistoryModel? = nil, backend: any TranslationBackend = RoutedTranslationBackend(), beforePreparing: @escaping @MainActor () async -> Void = {}) {
        self.packages = packages; self.beforePreparing = beforePreparing; self.history = history
        translation = ImageTranslationSession(backend: backend)
        translation.$complete.filter { $0 }.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.archiveResultIfNeeded() }
        }.store(in: &subscriptions)
    }
    func open(modelURL: URL?) async {
        let retained = archivedRevision == revision
        revision += 1; if retained { archivedRevision = revision }; let id = revision
        if let closing { await closing.value }
        guard revision == id, !Task.isCancelled else { return }
        active = true; self.modelURL = modelURL; translationModel = packages.selectedTranslation
        // Merely switching tabs must not unload or prepare multi-gigabyte models.
        error = nil
        if pendingImport { recognize() }
    }
    func importData(_ data: Data) {
        do {
            guard data.count <= 50*1024*1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3072] as CFDictionary) else { throw CameraError.image }
            pixels = cg; image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            pendingImport = true
            recognize()
        } catch { self.error = error.localizedDescription }
    }
    func recognize() {
        guard let pixels, active, !opening else { return }
        pendingImport = false
        revision += 1; let id = revision
        job?.cancel(); editedTranslation = nil; translation.clearScene(); recognizing = true; error = nil
        let source = source, target = target, automatic = automaticSource
        job = Task {
            defer { if revision == id { recognizing = false; opening = false; job = nil } }
            do {
                guard TranslationLanguage.details(target).connected(to: translationModel) else { throw PipelineError.modelLanguageUnavailable }
                if !translation.ready {
                    guard let modelURL else { throw ImagePreparationError.missingModel }
                    opening = true
                    await beforePreparing()
                    try Task.checkCancellation()
                    guard active, revision == id else { return }
                    await translation.prepare(modelURL, model: translationModel)
                    try Task.checkCancellation()
                    guard active, revision == id else { return }
                    opening = false
                    guard translation.ready else { throw ImagePreparationError.failed(translation.error) }
                }
                let result = try await ocr.recognize(pixels, source: automatic ? nil : source, forceOpen: false, modelURL: automatic ? nil : packages.ocr(source)?.installedURL, mergeParagraphs: true)
                try Task.checkCancellation()
                guard active, revision == id else { return }
                guard !result.blocks.isEmpty else { throw CameraError.noText }
                let detected: SpeechLanguage
                if automatic {
                    guard let language = TextLanguageDetection.detect(result.blocks.map(\.text).joined(separator: "\n")) else { throw PipelineError.textNeedsLanguage }
                    detected = language; self.source = language
                } else { detected = source }
                guard translationModel.supports(source: detected, target: target) else { throw PipelineError.modelLanguageUnavailable }
                translation.showsTranslationPartials = MacTranslationOptions.chunksEnabled()
                translation.usesDocumentContext = MacTranslationOptions.glossaryEnabled() && translationModel == .index9B && detected == .russian && target == .english
                translation.submit(result.blocks, source: detected, target: target, recognitionSeconds: result.processingSeconds)
            } catch is CancellationError {} catch { if revision == id { self.error = error.localizedDescription } }
        }
    }
    func close() async {
        if let closing { await closing.value; return }
        archiveResultIfNeeded()
        let retained = archivedRevision == revision
        active = false; revision += 1; if retained { archivedRevision = revision }; job?.cancel()
        let previous = job
        let task = Task {
            await translation.close(preservingResult: true); await previous?.value; await ocr.unload(); await archiving?.value
            recognizing = false; opening = false; job = nil
            closing = nil
        }
        closing = task; await task.value
    }
    func cancelTranslation() async {
        await close()
        await open(modelURL: modelURL)
    }
    func clear() async {
        await close()
        pendingImport = false
        image = nil; pixels = nil; editedTranslation = nil; translation.clearScene(); archivedRevision = nil; error = nil
        await open(modelURL: modelURL)
    }
    private func archiveResultIfNeeded() {
        guard let history, translation.complete, archivedRevision != revision, let png = renderedPNG() else { return }
        let id = revision, blocks = translation.translated, source = source, target = target
        archivedRevision = id
        archiving = Task {
            do { try await history.saveImage(png, blocks: blocks, source: source, target: target) }
            catch { if revision == id { self.error = error.localizedDescription } }
        }
    }
    func save() {
        guard pixels != nil, translation.complete else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = imageExportName()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = renderedPNG() else { error = CameraError.image.localizedDescription; return }
        do { try data.write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
    }
    func shareImage() -> URL? {
        guard let data = renderedPNG() else { return nil }
        // Reuse the private export lifetime: receiving apps can read after the picker closes.
        let directory = TextShareExport.directory()
        let url = directory.appendingPathComponent(imageExportName())
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic); return url
        }
        catch { self.error = error.localizedDescription; return nil }
    }
    private func imageExportName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date()) + ".png"
    }
    private func renderedPNG() -> Data? {
        guard let pixels, translation.complete else { return nil }
        let size = NSSize(width: pixels.width, height: pixels.height)
        let result = NSImage(size: size, flipped: false) { rect in
            NSImage(cgImage: pixels, size: size).draw(in: rect)
            for block in self.translation.translated {
                let b = block.box
                let box = NSRect(x: b.x*size.width, y: (1-b.y-b.height)*size.height, width: b.width*size.width, height: b.height*size.height)
                NSColor.black.withAlphaComponent(0.85).setFill(); box.fill()
                let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
                var fontSize = min(32, max(8, box.height*0.6))
                func attributes() -> [NSAttributedString.Key: Any] { [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.white, .paragraphStyle: paragraph] }
                while fontSize > 4 && (block.translation as NSString).boundingRect(with: NSSize(width: max(1,box.width-4), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributes()).height > box.height-4 { fontSize -= 0.5 }
                (block.translation as NSString).draw(with: box.insetBy(dx: 2, dy: 2), options: [.usesLineFragmentOrigin], attributes: attributes())
            }
            return true
        }
        guard let cg = result.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

private enum ImagePreparationError: LocalizedError {
    case missingModel, failed(String?)
    var errorDescription: String? {
        switch self {
        case .missingModel: L10n.text("Сначала скачайте модель перевода в разделе «Модели».")
        case .failed(let message): message ?? L10n.text("Не удалось подготовить перевод.")
        }
    }
}

struct CameraView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var model: CameraModel
    @ObservedObject var translation: ImageTranslationSession
    @AppStorage("showTechnicalInfo") private var showTechnicalInfo = false
    @State private var splitRatio: CGFloat = 0.5
    @State private var dragStart: CGFloat?
    @FocusState private var editingTranslation: Bool
    let expandTranslation: () -> Void
    let openModels: (PackageShortcut) -> Void
    var close: () -> Void = {}
    private var translatedText: String { model.translatedText }
    init(app: AppModel, expandTranslation: @escaping () -> Void, openModels: @escaping (PackageShortcut) -> Void = { _ in }) {
        self.app = app; model = app.camera; translation = app.camera.translation
        self.expandTranslation = expandTranslation; self.openModels = openModels
    }
    func withClose(_ action: @escaping () -> Void) -> Self { var copy = self; copy.close = action; return copy }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.text("Перевод изображения")).font(.title2)
                Spacer()
                Button { Task { await model.clear() } } label: { Image(systemName: "xmark") }.katCloseControl()
                    .accessibilityLabel(L10n.text("Очистить изображение")).help(L10n.text("Очистить изображение"))
                    .accessibilityIdentifier("image.clear").disabled(!model.hasResult || model.opening)
                    .katCancelShortcut()
            }
            LanguagePairPicker(selection: $app.languages, mode: .camera, model: app.packages.selectedTranslation, app: app, packages: app.packages, compact: true, showsDetails: false, detectedSource: translation.complete ? model.source : nil)
                .disabled(model.opening || translation.working || model.recognizing)
            HStack {
                Button(L10n.text("Открыть изображение…")) { openFile() }.macShortcut(.imageOpen)
                Button(L10n.text("Вставить изображение")) { paste() }.macShortcut(.imagePaste, enabled: !editingTranslation)
                Spacer()
                HStack(spacing: 8) {
                    ExpandTextButton(enabled: !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, identifier: "image.translation.expand", iconSize: 28, action: expandTranslation)
                    CopyTextButton(text: translatedText, title: L10n.text("Скопировать перевод"), iconSize: 28)
                        .help(L10n.text("Скопировать перевод"))
                        .accessibilityIdentifier("image.copyTranslation")
                    MacShareButton(prepareFile: { model.shareImage() }, title: L10n.text("Поделиться изображением"), iconSize: CGSize(width: 28, height: 28))
                        .help(L10n.text("Поделиться изображением"))
                        .accessibilityIdentifier("image.shareTranslation")
                        .disabled(!translation.complete)
                    Button { model.save() } label: {
                        Image(systemName: "square.and.arrow.down").frame(width: 28, height: 28)
                    }.accessibilityLabel(L10n.text("Сохранить перевод…"))
                        .help(L10n.text("Сохранить перевод…"))
                        .accessibilityIdentifier("image.saveTranslation")
                        .disabled(!translation.complete)
                }.font(.system(size: 18))
            }.disabled(model.opening)
            if let error = model.error ?? translation.error {
                if error == ImagePreparationError.missingModel.localizedDescription {
                    PackageHintButton(text: error, shortcut: .translation, packages: app.packages, open: openModels)
                } else { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            }
            if model.opening || model.recognizing || translation.working {
                HStack {
                    if let progress = translation.progress { TranslationProgressPanel(progress: progress) }
                    else { ProgressView(model.opening ? L10n.text("Подготовить перевод") : model.recognizing ? L10n.text("Распознаю текст…") : L10n.text("Перевожу надписи…")); Spacer() }
                    Button(L10n.text("Отмена")) { Task { await model.cancelTranslation() } }
                        .accessibilityIdentifier("image.translation.cancel")
                }
                // Preparation and per-block progress share one height. The image must not
                // rescale when a partial resets or the detailed progress first appears.
                .frame(height: 86)
            }
            GeometryReader { geometry in
                let available = max(1, geometry.size.width - 16)
                let minimum = min(240 / available, 0.4)
                let ratio = min(1 - minimum, max(minimum, splitRatio))
                HStack(spacing: 0) {
                    Group {
                        if let image = model.image { Image(nsImage: image).resizable().scaledToFit().accessibilityIdentifier("image.original") }
                        else { ContentUnavailableView(L10n.text("Выберите изображение"), systemImage: "photo", description: Text(L10n.text("Откройте файл или вставьте изображение из буфера обмена."))) }
                    }.frame(width: available * ratio, height: geometry.size.height).clipped()
                    ZStack {
                        Color.white.opacity(0.04)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                        Capsule().fill(KatTheme.accent.opacity(0.7)).frame(width: 4, height: 38)
                    }.frame(width: 16, height: geometry.size.height).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if dragStart == nil { dragStart = ratio }
                                splitRatio = min(1 - minimum, max(minimum, (dragStart ?? ratio) + value.translation.width / available))
                            }.onEnded { _ in dragStart = nil })
                        .pointerStyle(.columnResize)
                        .accessibilityElement().accessibilityLabel(L10n.text("Размер областей изображения"))
                        .accessibilityValue("\(Int(ratio * 100))%")
                        .accessibilityIdentifier("image.divider")
                        .accessibilityAdjustableAction { direction in
                            splitRatio = min(1 - minimum, max(minimum, ratio + (direction == .increment ? 0.05 : -0.05)))
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        if showTechnicalInfo, let timing = translation.timing {
                            TranslationTimingView(timing: timing, identifier: "image.timing")
                                .padding(.horizontal, 12).padding(.top, 12)
                        }
                    TextEditor(text: Binding(get: { model.displayedText }, set: { model.editedTranslation = $0 }))
                        .focused($editingTranslation)
                        .font(AppPlatform.translationFont).lineSpacing(4)
                        .scrollContentBackground(.hidden).padding(12)
                        .accessibilityIdentifier("image.translation")
                        .disabled(model.opening || model.recognizing || translation.working || !translation.complete)
                        .overlay(alignment: .topLeading) {
                            if !translation.complete && model.displayedText.isEmpty {
                                Text(L10n.text("Здесь появится перевод")).font(AppPlatform.translationFont)
                                    .foregroundStyle(.secondary).padding(16).allowsHitTesting(false)
                            }
                        }
                    }.frame(width: available * (1 - ratio), height: geometry.size.height)
                }
            }

        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black).tint(KatTheme.accent).katDesktopControls()
            .onChange(of: app.languages) { _, value in
                guard !app.importingScreenImage else { return }
                model.automaticSource = value.automaticActive(in: .camera)
                if !model.automaticSource { model.source = value.runtimeSource ?? .english }
                model.target = value.runtimeTarget ?? .russian
                model.recognize()
            }
    }
    private func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 50*1024*1024 else { throw CameraError.image }
            model.importData(try Data(contentsOf: url))
        } catch { model.error = error.localizedDescription }
    }
    private func paste() {
        do {
            if let data = try MacImagePasteboard.imageData(NSPasteboard.general) { model.importData(data) }
            else { model.error = L10n.text("В буфере обмена нет изображения.") }
        } catch { model.error = error.localizedDescription }
    }
}

/// A file copied in Finder also puts its icon on the pasteboard as TIFF; read the image file itself first.
enum MacImagePasteboard {
    static func imageData(_ board: NSPasteboard) throws -> Data? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        if let url = (board.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 50 * 1024 * 1024 else { throw CameraError.image }
            return try Data(contentsOf: url)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                     NSPasteboard.PasteboardType(UTType.heic.identifier)] {
            if let data = board.data(forType: type) { return data }
        }
        return nil
    }
}
