import SwiftUI
import OfflineCore

/// Where a "download … in Models" hint leads: the exact package the current pair is missing.
enum PackageShortcut: Hashable {
    case recognition(RecognitionPackageKind)
    /// Translation depends on the pair, the device and Auto, so this hint opens the translation card.
    case translation
    case voice(SpeechLanguage)
    case ocr(SpeechLanguage)
    static let translationCardID = cardID("translation")
    static func cardID(_ id: String) -> String { "models.card." + id }
}

extension PackageDownloadCoordinator {
    /// Every file of the shortcut's package, including installed ones (for progress).
    func files(for shortcut: PackageShortcut) -> [ModelDownloader] {
        switch shortcut {
        case .recognition(.whisper): return [whisper]
        case .recognition(.omnilingual): return [omnilingual]
        case .recognition(.ultra):
            return RecognitionPackages.definitions.first { $0.id == RecognitionCatalog.ultraID }.map { recognition.parts($0) } ?? []
        case .translation: return []
        case .voice(let language): return language.hasVoice ? components(selectedVoice(language)) : []
        case .ocr(let language): return ocr(language).map { [$0] } ?? []
        }
    }
    func missingFiles(for shortcut: PackageShortcut) -> [ModelDownloader] {
        files(for: shortcut).filter { !downloadReady($0) }
    }
    /// Card anchor in ModelsView; nil for packages managed on their own screens (voices, OCR).
    func modelsCardID(for shortcut: PackageShortcut) -> String? {
        switch shortcut {
        case .recognition(.ultra): return PackageShortcut.cardID(RecognitionCatalog.ultraID)
        case .recognition: return files(for: shortcut).first.map { PackageShortcut.cardID($0.model.id) }
        case .translation: return PackageShortcut.translationCardID
        case .voice, .ocr: return nil
        }
    }
    /// Received and total bytes while the package downloads, is checked or assembled; nil otherwise.
    func downloadProgress(for shortcut: PackageShortcut) -> (received: Int64, total: Int64)? {
        let items = files(for: shortcut)
        let active = items.contains { $0.isManaging || [.downloading, .checking].contains($0.state.phase) || installing.contains($0.model.id) }
            || (shortcut == .recognition(.ultra) && recognition.busyID == RecognitionCatalog.ultraID)
        guard active, !items.isEmpty else { return nil }
        return (items.reduce(0) { $0 + ($1.installedURL != nil ? $1.model.byteCount : min($1.state.receivedBytes, $1.model.byteCount)) },
                items.reduce(0) { $0 + $1.model.byteCount })
    }
    /// Starts the same flow as the package's own Download button.
    func start(_ shortcut: PackageShortcut) {
        guard restored else { return }
        switch shortcut {
        case .recognition(.whisper): whisper.start(resuming: whisper.state.phase == .paused)
        case .recognition(.omnilingual): downloadVoice(omnilingual)
        case .recognition(.ultra): recognition.start(ids: [RecognitionCatalog.ultraID])
        case .translation: break
        case .voice(let language): if language.hasVoice { downloadVoice(selectedVoice(language)) }
        case .ocr(let language): if let item = ocr(language), item.installedURL == nil { item.start(resuming: item.state.phase == .paused) }
        }
    }
}

/// A "download … in Models" hint that acts instead of naming a screen: it starts the missing package
/// with the usual size/cellular consent and opens its card, or leads to the download already running.
struct PackageHintButton: View {
    let text: String
    let shortcut: PackageShortcut
    @ObservedObject var packages: PackageDownloadCoordinator
    /// Opens the package's card; without it the hint downloads in place and shows progress itself.
    var open: ((PackageShortcut) -> Void)? = nil
    @StateObject private var request = DownloadRequest()
    var body: some View {
        let missing = packages.missingFiles(for: shortcut)
        let progress = packages.downloadProgress(for: shortcut)
        let title = packages.files(for: shortcut).first?.model.title ?? text
        Button {
            if progress == nil, !missing.isEmpty {
                Task { await request.request(missing.map(\.downloadAccessItem)) { packages.start(shortcut); open?(shortcut) } }
            } else { open?(shortcut) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(text, systemImage: "info.circle").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress {
                    CatDownloadProgressView(value: Double(progress.received), total: Double(max(1, progress.total)))
                    Text(open == nil ? L10n.text("Скачиваю: \(title)") : L10n.text("Показать загрузку"))
                        .foregroundStyle(open == nil ? Color.secondary : KatTheme.accent)
                } else {
                    Text(missing.isEmpty ? L10n.text("Открыть в «Моделях»") : L10n.text("Скачать"))
                        .fontWeight(.semibold).foregroundStyle(KatTheme.accent)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(request.checking || !packages.restored || (open == nil && (progress != nil || missing.isEmpty)))
        .accessibilityIdentifier("hint.package")
        .sheet(item: Binding(get: { request.prompt }, set: { if $0 == nil && request.prompt != nil { request.cancel() } }), onDismiss: request.didDismiss) { prompt in
            DownloadAccessPrompt(request: request, maximumBytes: prompt.maximumBytes)
        }
    }
}
