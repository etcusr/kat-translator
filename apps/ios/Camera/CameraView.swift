import SwiftUI
import AVFoundation
import PhotosUI
import Combine
import OfflineCore

/// Photos hands the picked image over as a file copy instead of one Data blob (audit 22.10, iOS C5).
struct PickedImageFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("PickedImage-" + UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedImageFile(url: copy)
        }
    }
}

struct CameraView: View, Equatable {
    /// The presenting view re-renders on every download progress tick, and the `close` closure made each new value
    /// look different, so the camera body ran again each time. All camera state comes from `app` (audit 22.10, iOS C6).
    nonisolated static func == (lhs: CameraView, rhs: CameraView) -> Bool { lhs.appID == rhs.appID }
    private let appID: ObjectIdentifier
    @ObservedObject var app: AppModel
    @ObservedObject var model: CameraModel
    @ObservedObject var translation: ImageTranslationSession
    /// Not observed: the coordinator republishes every download progress tick, which re-rendered the camera about
    /// 80 times a second during any download. Only the package state the camera shows is followed (audit 22.10, iOS C6).
    let packages: PackageDownloadCoordinator
    @State private var packageState = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPhoto: PhotosPickerItem?
    @StateObject private var importer = ImageImportSession()
    @State private var importError: String?
    @State private var share: SharedAudio?
    init(app: AppModel) { self.app = app; appID = ObjectIdentifier(app); model = app.camera; translation = app.camera.translation; packages = app.packages }
    var close: () -> Void = {}
    func withClose(_ action: @escaping () -> Void) -> CameraView { var copy = self; copy.close = action; return copy }
    @State private var zoom: CGFloat = 1
    @State private var frozenZoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var photoOffset: CGSize = .zero
    @GestureState private var dragging: CGSize = .zero
    @State private var showHistory = false
    @State private var showOCR = false
    @State private var showText = false
    var body: some View {
        let _ = packageState
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                ZStack {
                    if let image = model.frozen {
                        ZStack {
                            Image(uiImage: image).resizable().scaledToFit()
                            if let overlay = model.overlay { Image(uiImage: overlay).resizable().scaledToFit() }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(min(5, max(1, frozenZoom * pinch)))
                        .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { frozenZoom = min(5, max(1, frozenZoom * $0.magnification)); if frozenZoom == 1 { photoOffset = .zero } })
                        .offset(x: photoOffset.width + dragging.width, y: photoOffset.height + dragging.height)
                        .simultaneousGesture(DragGesture().updating($dragging) { value, state, _ in if frozenZoom > 1 { state = value.translation } }
                            .onEnded { value in if frozenZoom > 1 { photoOffset.width += value.translation.width; photoOffset.height += value.translation.height } })
                        .onTapGesture(count: 2) { frozenZoom = frozenZoom > 1 ? 1 : 2; photoOffset = .zero }
                    } else {
                        CameraPreview(capture: model.capture, orientationChanged: model.orient)
                        if let overlay = model.overlay {
                            Image(uiImage: overlay).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped().allowsHitTesting(false)
                        }
                    }
                }.clipped()
                if geometry.size.width > geometry.size.height {
                    HStack(spacing: 12) {
                        VStack(spacing: 8) {
                            landscapeHeader
                            Spacer(minLength: 0)
                            landscapeFooter
                        }.frame(maxWidth: .infinity)
                        VStack(spacing: 20) {
                            Spacer(minLength: 0)
                            shutterButton
                            galleryButton
                            Spacer(minLength: 0)
                        }.frame(width: 88).padding(.vertical, 8)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
                    }.padding(.horizontal, 12).padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) { cameraHeader; Spacer(minLength: 0); cameraControls }
                }
                if model.opening || model.takingPhoto {
                    ProgressView(model.takingPhoto ? L10n.text("Снимаю…") : L10n.text("Подготавливаю модель…"))
                        .padding().background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.background(.black).preferredColorScheme(.dark).tint(KatTheme.accent)
        .sheet(isPresented: $showHistory) { HistoryView(history: app.history) }
        .sheet(isPresented: $showOCR) {
            NavigationStack {
                Form {
                    Section(L10n.text("Распознавание текста")) {
                        Toggle(L10n.text("Использовать открытый OCR"), isOn: $model.forceOpenOCR).disabled(model.automaticSource || packages.ocr(model.source) == nil)
                        Text(L10n.text("По умолчанию используется Apple Vision, если он поддерживает язык. Открытый OCR-пакет нужен для неподдерживаемого языка или проверки резервной модели.")).font(.footnote)
                        if !model.engine.isEmpty { Text(L10n.text("Сейчас: ") + model.engine) }
                        if let item = packages.ocr(model.source) {
                            OCRPackageRow(item: item) { Task { await model.changedOptions() } }
                        } else { Text(HybridOCR.supports(model.source) ? L10n.text("Для этого языка используется встроенное офлайн-распознавание. Открытый OCR-пакет пока не подключён.") : L10n.text("Распознавание этого языка камерой пока не подключено. Выберите другой исходный язык или воспользуйтесь текстом/голосом.")).font(.footnote) }
                    }
                    Section {
                        Text(L10n.text("Наведите камеру на текст и нажмите «Снять». После перевода зафиксированного кадра его можно сохранить или отправить. Обработка выполняется на iPhone."))
                    }
                }.navigationTitle(L10n.text("Распознавание")).toolbar { Button(L10n.text("Готово")) { showOCR = false } }
            }
        }
        .sheet(isPresented: $showText) {
            NavigationStack {
                ScrollView { Text(translation.translated.map(\.translation).joined(separator: "\n\n"))
                    .font(.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(20)
                    .accessibilityIdentifier("camera.translationText") }
                    .navigationTitle(L10n.text("Перевод снимка")).toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { model.clearTextResult(); showText = false } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel(L10n.text("Очистить перевод снимка")).disabled(translation.translated.isEmpty)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            CopyTextButton(text: translation.translated.map(\.translation).joined(separator: "\n\n"), title: L10n.text("Скопировать перевод"))
                                .accessibilityIdentifier("camera.copyTranslation")
                        }
                        ToolbarItem(placement: .topBarTrailing) { Button(L10n.text("Готово")) { showText = false } }
                    }
            }
        }
        .onChange(of:app.languages) { _,pair in
            if let source = pair.runtimeSource, let target = pair.runtimeTarget {
                model.automaticSource = pair.automaticActive(in: .camera)
                if !model.automaticSource { model.source = source }
                model.target = target
                if packages.ocr(source) == nil { model.forceOpenOCR = false }
                Task { await model.changedOptions() }
            }
        }
        .onChange(of:model.forceOpenOCR) { _,_ in Task { await model.changedOptions() } }
        // Each render subscribes anew and @Published replays its current value on subscription: drop it, or the
        // state change re-renders, resubscribes and replays forever (a 100% CPU loop seen on iPhone).
        .onReceive(packages.$selectedTranslation.dropFirst().removeDuplicates()) { _ in packageState &+= 1 }
        .onReceive(packages.ocrRussian.$installedURL.dropFirst().merge(with: packages.ocrEnglish.$installedURL.dropFirst())) { _ in packageState &+= 1 }
        .onChange(of:selectedPhoto) { _,item in
            importError = nil
            guard let item else { importer.cancel(); return }
            importer.start(load: { try await item.loadTransferable(type: PickedImageFile.self) }, consume: { await model.importFile($0.url) })
        }
        .onChange(of:scenePhase) { _,phase in
            if phase == .background { importer.cancel(); Task { await app.closeCamera() } }
        }
        .onAppear { zoom = 1; model.capture.zoom(1) }
        .onDisappear { importer.cancel(); clearShare() }
        .sheet(item:Binding(get:{share},set:{ if let value=$0 {share=value} else {clearShare()} })) { item in AudioShareSheet(item:item,done:clearShare) }
    }
    private var cameraHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("Закрыть камеру")).accessibilityIdentifier("camera.close")
                Spacer()
                Text(L10n.text("Камера")).font(.headline)
                Spacer()
                Button { showHistory = true } label: { Image(systemName: "clock").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("История переводов")).accessibilityIdentifier("camera.history")
                Button { showOCR = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("Настройки распознавания"))
            }
            LanguagePairPicker(selection: $app.languages, mode: .camera, model: packages.selectedTranslation, app: app, packages: packages, compact: true, showsDetails: false, detectedSource: translation.complete ? model.source : nil)
                .disabled(importer.busy || model.opening || model.takingPhoto)
        }.padding(.horizontal, 14).padding(.bottom, 10).background(.black.opacity(0.75))
    }
    private var cameraControls: some View {
        VStack(spacing: 8) {
            if model.frozen == nil {
                HStack(spacing: 16) {
                    Text(L10n.text("Коснитесь текста для фокуса")).font(.caption2)
                    Spacer()
                    ForEach([CGFloat(1), 2], id: \.self) { factor in
                        Button { zoom = factor; model.capture.zoom(factor) } label: {
                            Text("\(Int(factor))×").font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                                .background(zoom == factor ? Color.white.opacity(0.25) : Color.clear, in: Circle())
                        }.accessibilityLabel(L10n.text("Увеличение \(Int(factor)) крат"))
                    }
                }
            } else { Text(L10n.text("Разведите пальцы, чтобы увеличить снимок")).font(.caption2) }
            Text(importer.busy ? L10n.text("Открываю изображение…") : model.status).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if let error = importError ?? importer.error ?? model.error ?? translation.error { Text(error).foregroundStyle(.orange).font(.caption).lineLimit(3) }
            if let message = model.message { Text(message).foregroundStyle(.green).font(.caption).lineLimit(2) }
            captureControls
        }.padding(.horizontal, 20).padding(.vertical, 10).background(.black.opacity(0.8))
    }
    private var landscapeHeader: some View {
        HStack(spacing: 8) {
            Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel(L10n.text("Закрыть камеру")).accessibilityIdentifier("camera.close")
            LanguagePairPicker(selection: $app.languages, mode: .camera, model: packages.selectedTranslation, app: app, packages: packages, compact: true, showsDetails: false, singleLine: true, detectedSource: translation.complete ? model.source : nil)
                .disabled(importer.busy || model.opening || model.takingPhoto)
            Button { showHistory = true } label: { Image(systemName: "clock").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("История переводов")).accessibilityIdentifier("camera.history")
                Button { showOCR = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                .accessibilityLabel(L10n.text("Настройки распознавания"))
        }.padding(4).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
    }
    private var landscapeFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                if model.frozen == nil {
                    ForEach([CGFloat(1), 2], id: \.self) { factor in
                        Button { zoom = factor; model.capture.zoom(factor) } label: {
                            Text("\(Int(factor))×").font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                                .background(zoom == factor ? Color.white.opacity(0.25) : Color.clear, in: Circle())
                        }.accessibilityLabel(L10n.text("Увеличение \(Int(factor)) крат"))
                    }
                    Text(importer.busy ? L10n.text("Открываю изображение…") : model.status).font(.caption).lineLimit(2)
                    Spacer(minLength: 0)
                } else { pictureActions }
            }
            if let error = importError ?? importer.error ?? model.error ?? translation.error { Text(error).foregroundStyle(.orange).font(.caption).lineLimit(2) }
            if let message = model.message { Text(message).foregroundStyle(.green).font(.caption).lineLimit(1) }
        }.padding(8).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
    private var pictureActions: some View {
        HStack {
                    Button { Task { await model.savePicture() } } label: { Label(L10n.text("Сохранить"), systemImage: "square.and.arrow.down") }.disabled(!model.canSave)
                    Spacer()
                    Button {
                        Task { do { share = SharedAudio(url: try await model.sharePicture()) } catch { importError = error.localizedDescription } }
                    } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.disabled(!model.canSave).accessibilityLabel(L10n.text("Поделиться снимком"))
                    Button { showText = true } label: { Image(systemName: "text.alignleft").frame(width: 44, height: 44) }
                        .disabled(translation.translated.isEmpty).accessibilityLabel(L10n.text("Текст перевода"))
                }
    }
    private var galleryButton: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    VStack { Image(systemName: "photo").font(.title2); Text(L10n.text("Галерея")).font(.caption) }.frame(width: 80, height: 72)
                }.disabled(model.opening || model.takingPhoto || importer.busy || !translation.ready)
    }
    private var shutterButton: some View {
        Button {
                    Task {
                        if !model.active { await app.openCamera() }
                        else if model.frozen != nil { frozenZoom = 1; photoOffset = .zero; await model.resume() }
                        else { await model.takePicture() }
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 3).frame(width: 60, height: 60)
                            if model.frozen == nil && model.active { Circle().fill(.white).frame(width: 48, height: 48) }
                            else { Image(systemName: "camera.fill").font(.title2).foregroundStyle(.white) }
                        }
                        Text(model.frozen != nil ? L10n.text("Ещё фото") : !model.active ? L10n.text("Запустить") : L10n.text("Снять")).font(.caption.weight(.semibold))
                    }
                }.disabled(model.opening || model.takingPhoto || importer.busy || (model.active && model.frozen == nil && !model.canCapture))
                    .accessibilityLabel(model.frozen != nil ? L10n.text("Вернуться к камере") : !model.active ? L10n.text("Запустить камеру") : L10n.text("Снять и перевести"))
                    .accessibilityIdentifier("camera.capture")
    }
    private var captureControls: some View {
        VStack(spacing: 8) {
            if model.frozen != nil { pictureActions }
            HStack {
                galleryButton
                Spacer()
                shutterButton
                Spacer()
                Color.clear.frame(width: 80, height: 72).accessibilityHidden(true)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func clearShare() { if let share {try? FileManager.default.removeItem(at:share.url)};share=nil }
}
private struct OCRPackageRow: View {
    @ObservedObject private var downloadAccess = DownloadAccessSettings.shared
    @ObservedObject var item: ModelDownloader
    let installed: () -> Void
    var body: some View {
        VStack(alignment:.leading) {
            Text(item.model.title+" · "+L10n.bytes(item.model.byteCount))
            if item.installedURL != nil { Label(L10n.text("Скачан и проверен"),systemImage:"checkmark.circle") }
            else if item.state.phase == .downloading {
                ProgressView(value:Double(item.state.receivedBytes),total:Double(item.model.byteCount))
                Button(L10n.text("Пауза")) { Task { await item.pause() } }
            } else if item.isManaging || item.state.phase == .checking { ProgressView(L10n.text("Проверяю пакет…")) }
            else { DownloadButton(item.state.phase == .paused ? L10n.text("Продолжить") : L10n.text("Скачать OCR-пакет"), items: [item]) { item.start(resuming:item.state.phase == .paused) }.disabled(!item.restored) }
            Toggle(L10n.text("Разрешить мобильный интернет"), isOn: $downloadAccess.allowCellular)
            if let error = item.state.error { Text(error).font(.footnote).foregroundStyle(.orange) }
        }.onChange(of:item.installedURL) { _,url in if url != nil { installed() } }
    }
}
private final class PreviewView: UIView {
    var capture: CameraCapture?
    var orientationChanged: ((CameraFrameOrientation) -> Void)?
    private var lastOrientation: CameraFrameOrientation?
    override func layoutSubviews() { super.layoutSubviews(); updateOrientation() }
    override func didMoveToWindow() { super.didMoveToWindow(); updateOrientation() }
    func updateOrientation() {
        guard let interface = window?.windowScene?.interfaceOrientation else { return }
        let orientation: CameraFrameOrientation
        switch interface {
        case .portrait: orientation = .portrait
        case .portraitUpsideDown: orientation = .portraitUpsideDown
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        default: return
        }
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(orientation.degrees) {
            connection.videoRotationAngle = orientation.degrees
        }
        guard orientation != lastOrientation else { return }
        lastOrientation = orientation
        // Avoid publishing SwiftUI state from inside layout/updateUIView.
        DispatchQueue.main.async { [weak self] in self?.orientationChanged?(orientation) }
    }
    private let focusRing = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus(_:))))
        focusRing.strokeColor = UIColor.systemYellow.cgColor; focusRing.fillColor = UIColor.clear.cgColor; focusRing.lineWidth = 2
        layer.addSublayer(focusRing)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func focus(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        capture?.focus(at: preview.captureDevicePointConverted(fromLayerPoint: point))
        focusRing.path = UIBezierPath(roundedRect: CGRect(x: point.x-28, y: point.y-28, width: 56, height: 56), cornerRadius: 6).cgPath
        focusRing.opacity = 1
        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0; fade.duration = 1.2
        focusRing.opacity = 0; focusRing.add(fade, forKey: "focus")
    }
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
private struct CameraPreview: UIViewRepresentable {
    let capture: CameraCapture
    let orientationChanged: (CameraFrameOrientation) -> Void
    func makeUIView(context:Context) -> PreviewView {
        let view=PreviewView();view.capture = capture; view.preview.session=capture.session;view.preview.videoGravity = .resizeAspectFill
        view.orientationChanged = orientationChanged
        view.updateOrientation()
        return view
    }
    func updateUIView(_ view:PreviewView,context:Context) {
        view.orientationChanged = orientationChanged
        view.updateOrientation()
    }
}
