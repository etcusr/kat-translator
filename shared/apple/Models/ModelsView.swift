import SwiftUI
#if os(macOS)
import AppKit
#endif
import OfflineCore

struct ModelsView: View {
    @ObservedObject var coordinator: PackageDownloadCoordinator
    @ObservedObject var session: ConversationPipeline
    @ObservedObject var model: AppModel
    let remove: (ModelDownloader) async -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloadAccess = DownloadAccessSettings.shared
    @State private var showLanguageSetup = false
    @State private var details: TranslationModel?
    private let memory = ProcessInfo.processInfo.physicalMemory
    var body: some View {
        NavigationStack {
            List {
                Section {
                    #if os(macOS)
                    Text(L10n.text("Модели выполняют перевод на Mac. После скачивания сеть для перевода не нужна."))
                    #else
                    Text(L10n.text("Модели выполняют перевод на iPhone. После скачивания сеть для перевода не нужна."))
                    #endif
                    Button(L10n.text("Настроить языки и загрузку")) { showLanguageSetup = true }
                        .accessibilityIdentifier("models.languageSetup")
                    Toggle(L10n.text("Разрешить мобильный интернет"), isOn: $downloadAccess.allowCellular)
                        .accessibilityIdentifier("models.allowCellular")
                    if !coordinator.restored { CatPreparationProgressView(label: L10n.text("Проверяю модели…")) }
                    else if coordinator.downloadingAll {
                        let progress = coordinator.setupProgress(coordinator.activeDownloadSetup, model: coordinator.selectedTranslation)
                        CatDownloadProgressView(value: Double(progress.received), total: Double(progress.total), isActive: progress.status == .downloading)
                        Button(L10n.text("Приостановить скачивание")) { Task { await coordinator.pauseAll() } }
                    } else if !coordinator.setupReady(coordinator.activeDownloadSetup, model: coordinator.selectedTranslation) {
                        let bytes = coordinator.setupBytes(coordinator.activeDownloadSetup, model: coordinator.selectedTranslation)
                        DownloadButton(L10n.text("Скачать модели · ") + L10n.bytes(bytes), items: coordinator.setupDownloadFiles(coordinator.activeDownloadSetup, model: coordinator.selectedTranslation)) {
                            coordinator.startAll()
                        }.disabled(!coordinator.translationTermsAccepted)
                    } else { Label(L10n.text("Пакеты для перевода готовы"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    if let error = coordinator.errors["downloadSpace"] { Text(error).foregroundStyle(.red) }
                    if let error = coordinator.errors["catalog"] { Text(error).foregroundStyle(.red) }
                    if let error = coordinator.errors["retiredTranslationModels"] { Text(error).foregroundStyle(.red) }
                }
                KatPanelSection(L10n.text("Модель перевода")) {
                    Text(ModelAdvice.startingPoint(memory: memory))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                    Button {
                        coordinator.setAutoTranslation(true); Task { await model.applyAutoTranslation() }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(L10n.text("Авто")).font(AppPlatform.panelHeading); Spacer(minLength: 4)
                                if coordinator.autoTranslation { Image(systemName: "checkmark.circle.fill") } }
                            Text(coordinator.strongDevice ? L10n.text("Мощное устройство: Index 9B для всех языков.")
                                 : L10n.text("Для каждой пары — установленная модель OPUS, иначе Index 2B или 9B."))
                                .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                            Label(L10n.text("Рекомендуется"), systemImage: "checkmark.seal.fill").font(AppPlatform.panelCaption).foregroundStyle(.tint)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("model.select.auto")
                        .disabled(session.isBusy || model.changingTranslation || !coordinator.restored)
                    // Direction packages are chosen per pair by Auto; they are not a manual model.
                    ForEach(TranslationModel.selectable.filter { $0 != .opusDirections }) { choice in
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                Task { await model.selectTranslation(choice) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(choice.title).font(AppPlatform.panelHeading)
                                        Spacer(minLength: 4)
                                        if !coordinator.autoTranslation && coordinator.selectedTranslation == choice { Image(systemName: "checkmark.circle.fill") }
                                    }
                                    Text(L10n.bytes(coordinator.translationBytes(choice)) + L10n.text(" скачать · заявлено: ") + ModelAdvice.languages(choice))
                                        .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                                    Text(ModelMemoryAdvice.approximateRAM(choice)).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                                    if !coordinator.autoTranslation && ModelMemoryAdvice.recommended(choice, physicalMemory: memory) {
                                        Label(L10n.text("Рекомендуется для вашего устройства"), systemImage: "checkmark.seal.fill")
                                            .font(AppPlatform.panelCaption).foregroundStyle(.tint)
                                            .accessibilityIdentifier("model.recommended." + choice.rawValue)
                                    }
                                    Text(ModelAdvice.recommendation(choice, memory: memory))
                                        .font(AppPlatform.panelCaption)
                                        .foregroundStyle(choice == .mil12B || (memory < 10_500_000_000 && choice.defersRecognitionLoading) ? Color.orange : Color.primary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("model.select." + choice.rawValue)
                                .accessibilityValue(coordinator.selectedTranslation == choice ? L10n.text("Выбрана") : L10n.text("Не выбрана"))
                                .disabled(session.isBusy || model.changingTranslation || !coordinator.restored)
                            Button { details = choice } label: {
                                Image(systemName: "info.circle").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless)
                                .accessibilityLabel(L10n.text("Подробнее о ") + choice.title)
                                .accessibilityIdentifier("model.info." + choice.rawValue)
                        }.padding(.vertical, 4)
                    }
                    Text(L10n.text("Число языков заявлено авторами моделей. Для выбранной модели в приложении доступны \(TranslationLanguage.supported(by: coordinator.selectedTranslation).count); озвучка и камера имеют отдельные ограничения."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                    Link(L10n.text("О модели и лицензии"), destination: coordinator.selectedTranslation.modelCardURL)
                    Button(L10n.text("Выгрузить из памяти")) { Task { await model.unload() } }
                        .disabled(!session.isReady || session.isBusy || model.changingTranslation)
                        .accessibilityIdentifier("model.unload").katStableAction()
                    Text(L10n.text("Выбор другой модели освобождает память предыдущей. Скачанные файлы остаются на телефоне; удалить их можно отдельной кнопкой ниже."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                }
                KatPanelSection(L10n.text("Распознавание речи")) {
                    Text(L10n.text("Авто: обычный Whisper для поддерживаемых им языков, включая русский и английский; Meta — для дополнительных. Ultra доступен вручную в настройках. Скачиваются только пакеты для выбранных языков."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                    Text(L10n.text("Первая подготовка распознавания может занять несколько минут. При смене языка может понадобиться загрузка другого распознавания."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                }
                ForEach(RecognitionPackages.definitions) { definition in
                    RecognitionPackageRow(definition: definition, packages: coordinator.recognition, remove: {
                        await model.unload(); await coordinator.recognition.remove(definition)
                    })
                }
                OpusPackageRow(package: coordinator.opus, coordinator: coordinator, remove: {
                    await model.closeCamera(); await model.unload(); await coordinator.pauseAll(); await coordinator.opus.remove()
                })
                KatPanelSection(L10n.text("OPUS · направления перевода")) {
                    let installed = coordinator.opusDirections.packages.filter { $0.directory != nil }.count
                    Text(L10n.text("Установлено \(installed) из \(coordinator.opusDirections.packages.count)"))
                        .accessibilityIdentifier("opus.directions.summary")
                    Text(L10n.text("Отдельные модели для пар языков без английского пакета. В режиме «Авто» нужные направления добавляются при настройке языков."))
                        .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                    NavigationLink(L10n.text("Выбрать направления")) {
                        OpusDirectionsView(coordinator: coordinator, directions: coordinator.opusDirections)
                    }.accessibilityIdentifier("opus.directions.open")
                }
                #if os(macOS)
                MacIndexPackageRow(package: coordinator.indexMLX, coordinator: coordinator, remove: {
                    await model.closeCamera(); await model.unload(); await coordinator.pauseAll(); await coordinator.indexMLX.remove()
                })
                ForEach([coordinator.whisper, coordinator.index2B], id: \.model.id) {
                    item in PackageRow(downloader: item, coordinator: coordinator, remove: { await remove(item) })
                }
                #else
                ForEach([coordinator.whisper] + coordinator.translationDownloaders, id: \.model.id) { item in
                    PackageRow(downloader: item, coordinator: coordinator, remove: { await remove(item) })
                }
                #endif
                KatPanelSection(L10n.text("Дополнительное распознавание")) {
                    Text(L10n.text("Meta Omnilingual добавляет голосовой ввод для 39 языков и вариантов из нашего списка, включая балийский. Для остальных остаётся Whisper. Новые направления экспериментальные; язык выбирается вручную."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                    Link("Meta Omnilingual · Apache 2.0", destination: URL(string: "https://huggingface.co/facebook/omniASR-CTC-300M-v2")!)
                }
                PackageRow(downloader: coordinator.omnilingual, coordinator: coordinator, remove: { await remove(coordinator.omnilingual) })
                KatPanelSection(L10n.text("Офлайн и восстановление")) {
                    Text(L10n.text("Приостановленную загрузку можно продолжить, если сервер сохранил данные. Изменение мобильной сети применяется только к новой загрузке. Выбор, скачивание и удаление голосов доступны в настройках → Голоса и образцы."))
                        .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
                }
            }.katScreenSurface().katPanelTypography().navigationTitle(L10n.text("Модели"))
                .katDoneToolbar { dismiss() }
                .katFullScreenCover(isPresented: $showLanguageSetup) { LanguageSetupView(model: model) }
                .sheet(item: $details) { choice in
                    NavigationStack {
                        List {
                            KatPanelSection(L10n.text("На этом устройстве")) {
                                LabeledContent(L10n.text("Всего RAM"), value: L10n.bytes(Int64(memory)))
                                Text(ModelAdvice.recommendation(choice, memory: memory))
                                Text(ModelAdvice.explanation(choice, memory: memory))
                            }
                            KatPanelSection(L10n.text("Языки и качество")) {
                                NavigationLink {
                                    ModelLanguagesView(model: choice)
                                        .katDoneToolbar(identifier: "model.info.close") { details = nil }
                                } label: {
                                    HStack {
                                        Text(L10n.text("Доступные языки"))
                                        Spacer()
                                        Text("\(TranslationLanguage.supported(by: choice).count)")
                                            .foregroundStyle(.secondary)
                                    }
                                }.accessibilityIdentifier("model.languages.open")
                                    .accessibilityValue("\(TranslationLanguage.supported(by: choice).count)")
                                Text(L10n.text("Заявлено авторами: ") + ModelAdvice.languages(choice))
                                Text(choice == .qwen9B ? L10n.text("Это общий языковой охват Qwen, а не подтверждение одинакового качества перевода на всех языках.") : L10n.text("Качество зависит от языка и текста. Число языков само по себе не означает лучший перевод."))
                                if choice != .opusBig {
                                    Text(L10n.text("В меню приложения пока \(TranslationLanguage.supported(by: choice).count) языков. Список зависит от выбранной модели. Для Qwen новые направления доступны для пробного перевода. Для речи нужны отдельные модели распознавания и голоса; для камеры — распознавание текста."))
                                }
                                Link(L10n.text("Источник: описание модели"), destination: choice.modelCardURL)
                                if choice == .opusBig {
                                    Text("Helsinki-NLP · CC BY 4.0")
                                    Link("OPUS-MT · ZLE → EN", destination: URL(string: "https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-zle-en")!)
                                    Link(L10n.text("Источник компактных файлов"), destination: URL(string: "https://huggingface.co/crash-sv/scribe-translate-ct2/tree/366ea5f4bd2bc417a7430006408a0c6cd72a9f91")!)
                                }
                            }
                            KatPanelSection(L10n.text("Память и скачивание")) {
                                Text(ModelMemoryAdvice.approximateRAM(choice))
                                LabeledContent(L10n.text("Файл модели"), value: L10n.bytes(coordinator.translationBytes(choice)))
                                Text(L10n.text("Размер файла — место в хранилище, а не расход RAM. При работе нужна дополнительная память для перевода, распознавания и озвучки. Общая RAM телефона не равна лимиту приложения."))
                                Text(L10n.text("Рекомендация предварительная: учитывает общий объём RAM и наши проверки, но не гарантирует стабильность при любой нагрузке. На непроверенном устройстве начните с короткой фразы."))
                            }
                        }.katScreenSurface().katPanelTypography().navigationTitle(choice.title).katInlineTitle()
                            .katDoneToolbar(identifier: "model.info.close") { details = nil }
                    }.katSheetClose(identifier: "model.info.close") { details = nil }
                }
        }.katSheetClose(identifier: "models.close") { dismiss() }
    }
}
private struct ModelLanguagesView: View {
    let model: TranslationModel
    @State private var query = ""
    private var background: Color {
        #if os(macOS)
        AppPlatform.panelBackground
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
    private var languages: [TranslationLanguage] { TranslationLanguage.supported(by: model) }
    private var matches: [TranslationLanguage] {
        languages.filter { $0.matches(query) }.sorted {
            $0.displayName.compare($1.displayName, options: [.caseInsensitive], locale: L10n.locale) == .orderedAscending
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.title).font(AppPlatform.panelHeading)
                Text(L10n.text("Языки перевода в приложении: \(languages.count)"))
                    .accessibilityIdentifier("model.languages.count")
                Text(L10n.text("Распознавание речи, озвучка и перевод изображений могут поддерживать меньше языков."))
                    .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n.text("Название или код языка"), text: $query)
                        .textFieldStyle(.plain).autocorrectionDisabled()
                        .accessibilityIdentifier("model.languages.search")
                }.padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }.padding(.horizontal, 16).padding(.top, 12)
            List {
                if matches.isEmpty { Text(L10n.text("Язык не найден")).foregroundStyle(.secondary) }
                ForEach(matches) { language in
                    HStack(spacing: 12) {
                        LanguageFlagBadge(languageID: language.id).frame(width: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.displayName).font(.system(size: 18))
                            Text(language.nativeName).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("model.languages.row." + language.id)
                }
            }.scrollContentBackground(.hidden).background(background)
        }.background(background).katPanelTypography().navigationTitle(L10n.text("Доступные языки")).katInlineTitle()
    }
}
private struct PackageRow: View {
    @ObservedObject var downloader: ModelDownloader
    @ObservedObject var coordinator: PackageDownloadCoordinator
    let remove: () async -> Void
    @State private var confirm = false
    var body: some View {
        KatPanelSection(downloader.model.title) {
            LabeledContent(L10n.text("Загрузка"), value: L10n.bytes(downloader.model.byteCount))
            if downloader.model.id == TranslationModel.mil12B.rawValue {
                Label(L10n.text("Не рекомендуется: на iPhone 17 Pro приложение закрывалось из-за нехватки памяти."), systemImage: "exclamationmark.triangle")
                    .font(AppPlatform.panelFootnote).foregroundStyle(.orange)
            }
            if coordinator.installing.contains(downloader.model.id) {
                CatPreparationProgressView(label: L10n.text("Распаковка и проверка…"))
                Button(L10n.text("Отменить"), role: .destructive) { Task { await coordinator.cancel(downloader) } }
            } else if downloader.isManaging || !downloader.restored { ProgressView(L10n.text("Подготовка…")) }
            else if downloader.state.phase == .downloading {
                CatDownloadProgressView(value: Double(downloader.state.receivedBytes), total: Double(downloader.model.byteCount))
                Text(L10n.bytes(downloader.state.receivedBytes)).font(AppPlatform.panelCaption)
                Button(L10n.text("Пауза")) { Task { await coordinator.pauseAll(); await downloader.pause() } }
                Button(L10n.text("Отменить"), role: .destructive) { Task { await coordinator.cancel(downloader) } }
            } else if downloader.state.phase == .checking {
                CatPreparationProgressView(label: L10n.text("Проверка целостности…"))
                Button(L10n.text("Отменить"), role: .destructive) { Task { await coordinator.cancel(downloader) } }
            } else if downloader.installedURL != nil {
                Label(coordinator.errors[downloader.model.id] == nil ? L10n.text("Скачано и проверено") : L10n.text("Нужна повторная установка"), systemImage: "checkmark.circle")
                    .accessibilityIdentifier("model.installed." + downloader.model.id)
                Button(L10n.text("Удалить"), role: .destructive) { confirm = true }
            } else {
                if downloader.state.phase == .paused {
                    CatDownloadProgressView(value: Double(downloader.state.receivedBytes), total: Double(downloader.model.byteCount), isActive: false)
                }
                Text(downloader.state.phase == .paused ? L10n.text("На паузе") : L10n.text("Не установлено"))
                    .foregroundStyle(.secondary)
                DownloadButton(downloader.state.phase == .paused ? L10n.text("Продолжить скачивание") : L10n.text("Скачать"), items: [downloader]) {
                    downloader.start(resuming: downloader.state.phase == .paused)
                }.disabled(!coordinator.restored || (TranslationModel(rawValue: downloader.model.id)?.requiresGemmaTerms == true && !coordinator.gemmaAccepted))
                    .accessibilityIdentifier("model.download." + downloader.model.id)
                #if os(macOS)
                Button(L10n.text("Импортировать скачанный файл…")) {
                    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url { Task { await downloader.importFile(url) } }
                }.disabled(!coordinator.restored || (TranslationModel(rawValue: downloader.model.id)?.requiresGemmaTerms == true && !coordinator.gemmaAccepted))
                #endif
            }
            if let error = coordinator.errors[downloader.model.id] ?? downloader.state.error { Text(error).foregroundStyle(.red).font(AppPlatform.panelFootnote) }
        }
        .confirmationDialog(L10n.text("Удалить пакет?"), isPresented: $confirm) {
            Button(L10n.text("Удалить"), role: .destructive) { Task { await remove() } }
        } message: { Text(L10n.text("Перед удалением активная обработка остановится. Пакет можно скачать снова.")) }
    }
}

/// Conservative guidance, not a measured working-set requirement or a compatibility guarantee.
enum ModelAdvice {
    static func languages(_ model: TranslationModel) -> String {
        switch model {
        case .opusBig: return L10n.text("35 языков через направления OPUS · этот пакет: английский ↔ русский, украинский, белорусский")
        case .gemma4B: return L10n.text("55 языков")
        case .index9B, .index2B: return L10n.text("150 языков")
        case .opusDirections: return L10n.text("Отдельные направления OPUS")
        case .qwen9B: return L10n.text("201 язык и диалект")
        case .mil4B, .mil12B: return L10n.text("46 языков и вариантов")
        }
    }
    static func startingPoint(memory: UInt64) -> String {
        L10n.text("Index 2B — 150 языков, быстрый. Index 9B — максимальное качество, медленнее. OPUS Big — компактные модели для отдельных направлений (русский ↔ европейские языки, английский ↔ ~30 языков); каждое направление скачивается отдельно.")
    }
    static func recommendation(_ model: TranslationModel, memory: UInt64) -> String {
        switch model {
        case .opusBig, .opusDirections: return L10n.text("Компактный офлайн-переводчик · меньше загрузка и расход памяти")
        case .index2B: return L10n.text("150 языков · примерно в 3 раза быстрее 9B")
        case .mil12B: return L10n.text("Не рекомендуется для iPhone")
        case .index9B: return memory >= 10_500_000_000 ? L10n.text("Начните с этой модели") : L10n.text("Много памяти · для поддерживаемых пар можно выбрать OPUS Big")
        case .qwen9B: return memory >= 10_500_000_000 ? L10n.text("Альтернатива Index · сравните качество") : L10n.text("Много памяти · для поддерживаемых пар можно выбрать OPUS Big")
        case .gemma4B: return memory < 6_000_000_000 ? L10n.text("Компактная · запас памяти ограничен") : L10n.text("Компактная · меньше расход памяти")
        case .mil4B: return memory < 6_000_000_000 ? L10n.text("Компактная · запас памяти ограничен") : L10n.text("Компактная альтернатива · для сравнения")
        }
    }
    static func explanation(_ model: TranslationModel, memory: UInt64) -> String {
        switch model {
        case .opusBig, .opusDirections:
            return L10n.text("Меньше объём загрузки и расход памяти. Перевод без интернета с английского на русский, украинский и белорусский и обратно. Качество сложных текстов может уступать Index.")
        case .index2B:
            return L10n.text("Index 2B — быстрая модель для 150 языков. Для максимального качества выберите Index 9B. Модель перевода общая для нескольких языков.")
        case .mil12B:
            return L10n.text("При использовании MiLMMT-46 12B на iPhone 17 Pro iOS закрывала приложение из-за нехватки памяти. Для повседневного перевода выберите Index 9B или Qwen 9B. На других устройствах устойчивость 12B не подтверждена.")
        case .index9B, .qwen9B:
            return memory >= 10_500_000_000
                ? L10n.text("На iPhone 17 Pro эти модели уже выполняли переводы. Более длинный текст, другие приложения и одновременная работа с речью могут увеличить нагрузку. Качество оценивайте на нужных вам языках.")
                : L10n.text("Эта модель требует много памяти. Для поддерживаемых языковых пар OPUS Big расходует меньше памяти; работоспособность Index на этом устройстве не подтверждена.")
        case .gemma4B, .mil4B:
            return L10n.text("Более лёгкий вариант, если 9B не помещается или работает медленно. В наших пробах компактные модели допускали смысловые ошибки; меньший расход памяти не означает то же качество.")
        }
    }
}

private struct RecognitionPackageRow: View {
    let definition: RecognitionPackage
    @ObservedObject var packages: RecognitionPackages
    let remove: () async -> Void
    @State private var confirmRemove = false
    var body: some View {
        KatPanelSection(definition.title) {
            LabeledContent(L10n.text("Загрузка"), value: L10n.bytes(definition.manifest.expandedBytes))
            if packages.directories[definition.id] != nil {
                Label(L10n.text("Скачано и проверено"), systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("model.installed." + definition.id)
                Button(L10n.text("Удалить"), role: .destructive) { confirmRemove = true }
            } else if packages.busyID == definition.id {
                let items = packages.parts(definition)
                let received = items.reduce(Int64(0)) { $0 + ($1.installedURL != nil ? $1.model.byteCount : min($1.state.receivedBytes, $1.model.byteCount)) }
                CatDownloadProgressView(value: Double(received), total: Double(definition.manifest.expandedBytes), isActive: items.contains { $0.state.phase == .downloading })
                Button(L10n.text("Пауза")) { Task { await packages.pause() } }
            } else {
                DownloadButton(L10n.text("Скачать"), items: packages.parts(definition)) { packages.start(ids: [definition.id]) }
                    .disabled(packages.busyID != nil || packages.parts(definition).contains { !$0.restored })
                    .accessibilityIdentifier("model.download." + definition.id)
            }
            Link(definition.license, destination: definition.sourceURL).font(AppPlatform.panelCaption)
            if let error = packages.errors[definition.id] { Text(error).font(AppPlatform.panelFootnote).foregroundStyle(.orange) }
        }.confirmationDialog(L10n.text("Удалить пакет?"), isPresented: $confirmRemove) {
            Button(L10n.text("Удалить"), role: .destructive) { Task { await remove() } }
        }
    }
}
