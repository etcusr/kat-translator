import SwiftUI
import AVFoundation
import OfflineCore
@MainActor final class VoicePreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing: String?
    @Published private(set) var error: String?
    private var player: AVAudioPlayer?
    func play(_ id: String) {
        if playing == id { stop(); return }
        stop(); error = nil
        do {
            guard let url = Bundle.main.url(forResource: id, withExtension: "m4a") else { throw PipelineError.invalidAudio }
        #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
        #if os(iOS)
            try AVAudioSession.sharedInstance().setActive(true)
        #endif
            let player = try AVAudioPlayer(contentsOf: url); self.player = player; player.delegate = self; playing = id
            guard player.play() else { throw PipelineError.invalidAudio }
        } catch { self.error = error.localizedDescription; stop() }
    }
    func stop() { player?.stop(); player = nil; deactivateAudioSession(); playing = nil }
    private func deactivateAudioSession() {
        #if os(iOS)
        if playing != nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        #endif
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in if self?.player === player { self?.stop() } }
    }
}
struct VoiceSettingsView: View {
    let model: AppModel
    @ObservedObject var packages: PackageDownloadCoordinator
    @ObservedObject var preview: VoicePreviewPlayer
    @State private var applying = false
    private let initialLanguage: SpeechLanguage?
    init(model: AppModel, initialLanguage: SpeechLanguage? = nil) {
        self.model = model; packages = model.packages; preview = model.voicePreview; self.initialLanguage = initialLanguage
    }
    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section(L10n.text("Все языки")) {
                Text(L10n.text("Готово языков: \(packages.readyVoiceLanguageCount) из \(SpeechLanguage.allCases.filter(\.hasVoice).count)"))
                    .accessibilityIdentifier("voices.coverage")
                if packages.downloadingVoices {
                    CatDownloadProgressView(value: Double(packages.voiceQueueReceivedBytes), total: Double(max(1, packages.voiceQueueTotalBytes)), isActive: packages.voiceQueueItems.contains { $0.state.phase == .downloading }, label: packages.voiceQueueStatus)
                    Text(L10n.bytes(packages.voiceQueueReceivedBytes)
                         + L10n.text(" из ") + L10n.bytes(packages.voiceQueueTotalBytes))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Button(L10n.text("Приостановить скачивание голосов")) { Task { await packages.pauseVoiceDownloads() } }
                } else if !packages.missingVoiceDownloaders.isEmpty {
                    DownloadButton(L10n.text("Скачать недостающие голоса"), items: packages.missingVoiceDownloaders) { packages.startAllVoices() }
                        .disabled(!packages.restored).accessibilityIdentifier("voices.downloadAll")
                    Text(L10n.bytes(packages.missingVoiceBytes))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.text("Supertonic и OmniVoice — общие пакеты для нескольких языков. Остальные голоса скачиваются отдельно. Ваш выбор голоса сохраняется."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error = preview.error { Text(error).foregroundStyle(.orange) }
            ForEach(SpeechLanguage.allCases.filter(\.hasVoice), id: \.self) { language in
                Section(TranslationLanguage.name(language.rawValue)) {
                    // Shared packages appear in multiple sections. List row identity
                    // must include the language or SwiftUI reuses the first row's actions.
                    ForEach(packages.voices(language).map { (id: language.rawValue + "." + $0.model.id, item: $0) }, id: \.id) { choice in
                        let item = choice.item
                        VoiceChoiceRow(item: item, packages: packages, preview: preview, language: language, applying: applying, modelBusy: model.session.isBusy, chooseWayu: { voice in
                            applying = true; await model.selectWayuVoice(voice); applying = false
                        }, apply: {
                            applying = true; await model.selectVoice(item, language: language); applying = false
                        }, remove: {
                            applying = true; await model.removeModel(item); applying = false
                        })
                    }
                }.id(language)
            }
            Text(L10n.text("Голос скачивается только по нажатию. Образец создан этой же моделью заранее; время синтеза на вашем телефоне измеряется отдельно.")).font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle(L10n.text("Голоса")).katInlineTitle()
            .onAppear { if let initialLanguage { proxy.scrollTo(initialLanguage, anchor: .top) } }
            .onDisappear { preview.stop() }
        }
    }
}
private struct VoiceChoiceRow: View {
    @ObservedObject var item: ModelDownloader
    @ObservedObject var packages: PackageDownloadCoordinator
    @ObservedObject var preview: VoicePreviewPlayer
    let language: SpeechLanguage
    let applying: Bool
    let modelBusy: Bool
    let chooseWayu: (WayuVoice) async -> Void
    let apply: () async -> Void
    let remove: () async -> Void
    @State private var confirmRemoval = false
    private var previewID: String? {
        let id = item === packages.wayuVoice ? "wayu-" + WayuVoice.selected.rawValue : item.model.id + ((item.model.id == ModelCatalog.supertonicVoice.id || item.model.id == "omnivoice-q8-base") ? "-" + language.rawValue : "")
        // A multilingual voice needs its own recording for this exact language.
        // Missing samples stay absent; never substitute another language's audio.
        return Bundle.main.url(forResource: id, withExtension: "m4a") == nil ? nil : id
    }
    private var groupedDownloadActive: Bool {
        packages.downloadingVoices && packages.voiceQueueItems.contains { queued in
            packages.components(item).contains { $0 === queued }
        }
    }
    private var hasPendingDownload: Bool {
        packages.components(item).contains { component in
            packages.installing.contains(component.model.id) || [.checking, .downloading, .paused].contains(component.state.phase)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.model.title).font(.headline)
                if packages.selectedVoice(language) === item { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Text(L10n.bytes(packages.components(item).reduce(0) { $0 + $1.model.byteCount })).font(.caption).foregroundStyle(.secondary)
            if item === packages.wayuVoice {
                Picker(L10n.text("Голос Wayu"), selection: Binding(get: { WayuVoice.selected }, set: { voice in Task { await chooseWayu(voice) } })) {
                    ForEach(WayuVoice.allCases) { voice in Text(voice.title).tag(voice) }
                }.disabled(applying || modelBusy).accessibilityIdentifier("voices.wayu.speaker")
            }
            if let previewID {
                Button { preview.play(previewID) } label: {
                    Label(preview.playing == previewID ? L10n.text("Остановить образец") : L10n.text("Послушать образец"), systemImage: preview.playing == previewID ? "stop.fill" : "play.fill")
                }.buttonStyle(.borderless).accessibilityIdentifier("voices.preview." + language.rawValue + "." + item.model.id)
            }
            if item === packages.wayuVoice {
                Link("Wayu Kokoro · Apache 2.0", destination: URL(string: "https://huggingface.co/kunato/wayu-kokoro-thai-v1/tree/50d7f60e41ac118e5bb92b0ba52c30bb7830103c")!).font(.caption)
                Text(L10n.text("12 голосов в одном пакете. Для тайского текста; редкие английские имена могут не озвучиваться.")).font(.caption).foregroundStyle(.secondary)
            } else if let definition = AdditionalVoiceCatalog.catalog.package(containing: item.model.id) {
                Link(L10n.text("Источник и условия голоса"), destination: definition.sourceURL).font(.caption)
                Text(definition.license).font(.caption).foregroundStyle(.secondary)
                if item.model.id == "omnivoice-q8-base" {
                    Text(L10n.text("Общий пакет OmniVoice: \(definition.languageAliases?.count ?? 1) языков в приложении. Скачивается один раз. Требует больше памяти и времени, чем лёгкие голоса; качество зависит от языка. Первый запуск может занять несколько десятков секунд.")).font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.text("Экспериментальный голос. Синтез проверен; произношение пока не проверено носителем языка.")).font(.caption).foregroundStyle(.secondary)
            } else if item === packages.balineseVoice {
                Link("Meta MMS · CC BY-NC 4.0", destination: URL(string: "https://huggingface.co/facebook/mms-tts-ban")!).font(.caption)
                Link(L10n.text("Преобразование в ONNX: Will Wade"), destination: URL(string: "https://huggingface.co/willwade/mms-tts-multilingual-models-onnx")!).font(.caption)
                Text(L10n.text("Экспериментальный балийский голос для текста латиницей и некоммерческого использования. Произношение пока не проверено носителем языка.")).font(.caption).foregroundStyle(.secondary)
            } else if item.model.id == ModelCatalog.chineseVoice.id {
                Link(L10n.text("Huayan · условия исходных данных не указаны"), destination: URL(string: "https://huggingface.co/rhasspy/piper-voices/blob/main/zh/zh_CN/huayan/medium/MODEL_CARD")!).font(.caption)
            } else if item.model.id == ModelCatalog.supertonicVoice.id {
                Link("Supertonic 3 · OpenRAIL-M", destination: URL(string: "https://huggingface.co/Supertone/supertonic-3")!).font(.caption)
            }
            if packages.voiceDirectories[item.model.id] != nil {
                Button(L10n.text("Использовать этот голос")) { Task { await apply() } }.disabled(applying || packages.selectedVoice(language) === item).buttonStyle(.borderless)
            } else if packages.components(item).count > 1 && groupedDownloadActive {
                CatDownloadProgressView(value: Double(packages.components(item).reduce(0) { $0 + ($1.installedURL != nil ? $1.model.byteCount : $1.state.receivedBytes) }), total: Double(packages.components(item).reduce(0) { $0 + $1.model.byteCount }), isActive: packages.components(item).contains { $0.state.phase == .downloading })
                Button(L10n.text("Пауза")) { Task { await packages.pauseVoiceDownloads() } }.buttonStyle(.borderless)
            } else if packages.installing.contains(item.model.id) || item.state.phase == .checking || item.isManaging {
                CatPreparationProgressView(label: L10n.text("Проверяю голос…"))
            } else if item.state.phase == .downloading {
                CatDownloadProgressView(value: Double(item.state.receivedBytes), total: Double(item.model.byteCount))
                Button(L10n.text("Пауза")) { Task { await item.pause() } }.buttonStyle(.borderless)
            } else {
                if item.state.phase == .paused {
                    CatDownloadProgressView(value: Double(item.state.receivedBytes), total: Double(item.model.byteCount), isActive: false)
                }
                DownloadButton(item.state.phase == .paused ? L10n.text("Продолжить скачивание") : L10n.text("Скачать голос"), items: packages.components(item)) { packages.downloadVoice(item) }.disabled(!packages.restored).buttonStyle(.borderless).accessibilityIdentifier("voices.download." + item.model.id)
            }
            if packages.components(item).contains(where: { $0.installedURL != nil }) && !packages.installing.contains(item.model.id) {
                Button(L10n.text("Удалить голос"), role: .destructive) { confirmRemoval = true }
                    .disabled(applying || item.isManaging).buttonStyle(.borderless)
            }
            if hasPendingDownload {
                Button(L10n.text("Отменить скачивание"), role: .destructive) { Task { await packages.cancel(item) } }
                    .disabled(applying || item.isManaging).buttonStyle(.borderless)
            }
            ForEach(packages.components(item), id: \.model.id) { component in
                if let error = packages.errors[component.model.id] ?? component.state.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }.padding(.vertical, 8)
            .confirmationDialog(L10n.text("Удалить голос?"), isPresented: $confirmRemoval) {
                Button(L10n.text("Удалить"), role: .destructive) { Task { await remove() } }
            } message: { Text(((item.model.id == ModelCatalog.supertonicVoice.id || item.model.id == "omnivoice-q8-base") ? L10n.text("Общий пакет удалится для всех использующих его языков. ") : "") + L10n.text("Голос можно скачать снова. После удаления выбранного голоса озвучка будет недоступна, пока вы не скачаете его или не выберете другой.")) }
    }
}
