import SwiftUI
import OfflineCore

/// OCR settings share the app's package coordinator; navigation never starts a separate download owner.
struct OCRSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var packages: PackageDownloadCoordinator
    #if os(iOS)
    @ObservedObject private var camera: CameraModel
    #endif
    init(model: AppModel) {
        self.model = model
        packages = model.packages
        #if os(iOS)
        camera = model.camera
        #endif
    }
    var body: some View {
        List {
            #if os(iOS)
            Section(L10n.text("Распознавание текста")) {
                Toggle(L10n.text("Использовать открытый OCR"), isOn: $camera.forceOpenOCR)
                    .disabled(model.languages.automaticActive(in: .camera) || model.languages.runtimeSource.flatMap { packages.ocr($0) } == nil)
                    .accessibilityIdentifier("settings.ocr.openSource")
                Text(L10n.text("По умолчанию используется Apple Vision, если он поддерживает язык. Открытый OCR-пакет нужен для неподдерживаемого языка или проверки резервной модели."))
                    .font(.footnote).foregroundStyle(.secondary)
                if !camera.engine.isEmpty { LabeledContent(L10n.text("Сейчас: "), value: camera.engine) }
            }
            ForEach([packages.ocrRussian, packages.ocrEnglish], id: \.model.id) { item in
                PackageRow(downloader: item, coordinator: packages, remove: { await model.removeModel(item) })
            }
            #else
            Section(L10n.text("Распознавание текста")) {
                Label("Apple Vision", systemImage: "text.viewfinder")
                Text(L10n.text("На Mac используется встроенное офлайн-распознавание Apple Vision. Дополнительные OCR-пакеты не требуются."))
                    .foregroundStyle(.secondary)
            }
            #endif
        }.katSettingsList().navigationTitle(L10n.text("Распознавание текста")).katInlineTitle()
            .disabled(packages.cancellingBatch)
    }
}
