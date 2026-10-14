import SwiftUI
import OfflineCore

struct OpusPackageRow: View {
    @ObservedObject var package: OpusPackage
    @ObservedObject var coordinator: PackageDownloadCoordinator
    let remove: () async -> Void
    @State private var confirmRemoval = false
    var body: some View {
        KatPanelSection(TranslationModel.opusBig.title) {
            LabeledContent(L10n.text("Загрузка"), value: L10n.bytes(OpusPackage.bytes))
            Text(L10n.text("Английский ↔ русский, украинский и белорусский. Обе модели входят в один пакет."))
                .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
            if package.directory != nil {
                Label(L10n.text("Скачано и проверено"), systemImage: "checkmark.circle")
                    .accessibilityIdentifier("model.installed." + TranslationModel.opusBig.rawValue)
                Button(L10n.text("Удалить"), role: .destructive) { confirmRemoval = true }
            } else if package.installing {
                CatPreparationProgressView(label: L10n.text("Проверка целостности…"))
            } else if package.downloading {
                CatDownloadProgressView(value: Double(package.progress.received), total: Double(package.progress.total))
                Button(L10n.text("Пауза")) { Task { await coordinator.pauseAll() } }
                Button(L10n.text("Отменить"), role: .destructive) { Task { await coordinator.cancelOpus() } }
            } else {
                DownloadButton(L10n.text("Скачать"), items: package.downloaders) { coordinator.startOpus() }
                    .disabled(!coordinator.restored)
                    .accessibilityIdentifier("model.download." + TranslationModel.opusBig.rawValue)
            }
            if let error = package.error ?? package.downloaders.compactMap({ $0.state.error }).first {
                Text(error).foregroundStyle(.red).font(AppPlatform.panelFootnote)
            }
        }.confirmationDialog(L10n.text("Удалить пакет?"), isPresented: $confirmRemoval) {
            Button(L10n.text("Удалить"), role: .destructive) { Task { await remove() } }
        } message: { Text(L10n.text("Перед удалением активная обработка остановится. Пакет можно скачать снова.")) }
    }
}
