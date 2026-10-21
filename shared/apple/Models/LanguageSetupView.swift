import SwiftUI
import OfflineCore

/// Name on the left, size at the right edge on both platforms (macOS LabeledContent put the
/// value right after the name outside a Form).
private struct SizeRow: View {
    let title: String, value: String, identifier: String?
    init(_ title: String, _ value: String, identifier: String? = nil) { self.title = title; self.value = value; self.identifier = identifier }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).accessibilityIdentifier(identifier ?? "setup.size.title")
            Spacer(minLength: 0)
            Text(value).foregroundStyle(.secondary).monospacedDigit().accessibilityIdentifier("setup.size")
        }
    }
}

struct LanguageSetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var packages: PackageDownloadCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var setup: LanguageSetup
    @State private var primarySearch = ""
    @State private var targetSearch = ""
    @State private var started = false
    @State private var applying = false
    @State private var probe: DeviceProbeResult? = DeviceProbe.saved
    @State private var probing = false
    @FocusState private var focusedColumn: Int?
    init(model: AppModel) {
        self.model = model; packages = model.packages
        _setup = State(initialValue: model.packages.languageSetup)
    }
    private var choice: TranslationModel { packages.autoTranslation ? packages.selectedTranslation : setup.recommendedTranslation(strongDevice: probe?.strong ?? false) }
    private var autoPlan: (models: [TranslationModel], directions: [OpusDirectionPackage]) { packages.autoPlan(setup) }
    private var bytes: Int64 { packages.setupBytes(setup, model: choice) }
    private var complete: Bool { packages.setupReady(setup, model: choice) }
    private func size(_ value: Int64) -> String { L10n.bytes(value) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    deviceCheck
                    if probe != nil {
                    Text(L10n.text("Выберите языки. Общие модели скачиваются один раз, остальные можно добавить позже."))
                        .font(AppPlatform.panelBody).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 12) {
                        languageColumn(primary: true)
                        languageColumn(primary: false)
                    }.disabled(started || applying)
                    // Leading alignment: centered toggles of different widths looked misaligned on Mac.
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(L10n.text("Распознавание речи"), isOn: $setup.recognition).accessibilityIdentifier("setup.recognition")
                        Toggle(L10n.text("Озвучивание перевода"), isOn: $setup.speech).accessibilityIdentifier("setup.speech")
                    }.font(AppPlatform.panelBody).frame(maxWidth: .infinity, alignment: .leading)
                    // The iOS switch draws its track a few points past its frame; keep it inside the card edge.
                    #if os(iOS)
                    .padding(.trailing, 4)
                    #endif
                    .disabled(started || applying)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.text("Нужные модели")).font(AppPlatform.panelHeading)
                        if packages.autoTranslation {
                            ForEach(autoPlan.models) { item in
                                SizeRow(L10n.text("Перевод") + " · " + item.title, size(packages.translationBytes(item)))
                            }
                            ForEach(autoPlan.directions) { item in
                                SizeRow(L10n.text("Перевод") + " · OPUS " + item.route.direction, size(item.route.bytes))
                            }
                        } else {
                        SizeRow(L10n.text("Перевод") + " · " + choice.title, size(packages.translationBytes(choice)))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("setup.translation.model")
                            .accessibilityValue(choice.title)
                        }
                        Text(choice == .opusBig
                             ? ModelAdvice.explanation(choice, memory: ProcessInfo.processInfo.physicalMemory)
                             : L10n.text("Компактная замена сопоставимого качества пока не найдена. Модель перевода общая для нескольких языков."))
                            .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                        if choice == .qwen9B {
                            Text(L10n.text("Часть выбранных языков доступна только в Qwen. Качество этих направлений экспериментальное."))
                                .font(AppPlatform.panelCaption).foregroundStyle(.orange)
                        }
                        ForEach(RecognitionPackages.definitions.filter { setup.recognitionIDs.contains($0.id) }) { item in
                            SizeRow(item.title, size(item.parts.reduce(0) { $0 + $1.byteCount }), identifier: "setup.asr." + item.id)
                        }
                        if setup.recognitionIDs.contains(ModelDescriptor.turbo.id) {
                            SizeRow(packages.whisper.model.title, size(packages.whisper.model.byteCount), identifier: "setup.asr." + ModelDescriptor.turbo.id)
                        }
                        if setup.recognitionIDs.contains(LanguageSetup.omnilingualID) {
                            SizeRow("Meta Omnilingual", size(packages.omnilingual.model.byteCount))
                        }
                        ForEach(packages.setupVoices(setup), id: \.model.id) { item in
                            SizeRow(item.model.title, size(packages.components(item).reduce(0) { $0 + $1.model.byteCount }))
                        }
                        if !setup.missingRecognition.isEmpty {
                            Text(L10n.text("Без распознавания: ") + names(setup.missingRecognition)).font(AppPlatform.panelCaption).foregroundStyle(.orange)
                        }
                        if !setup.missingSpeech.isEmpty {
                            Text(L10n.text("Без озвучки: ") + names(setup.missingSpeech)).font(AppPlatform.panelCaption).foregroundStyle(.orange)
                        }
                    }.font(AppPlatform.panelBody).frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .contain).accessibilityIdentifier("setup.panel.models")
                    Text(ModelMemoryAdvice.approximateRAM(choice)).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                    if !ModelMemoryAdvice.recommended(choice, physicalMemory: ProcessInfo.processInfo.physicalMemory) {
                        Text(ModelAdvice.recommendation(choice, memory: ProcessInfo.processInfo.physicalMemory)).font(AppPlatform.panelCaption).foregroundStyle(.orange)
                    }
                    #if os(iOS)
                    Text(L10n.text("Можно свернуть приложение: загрузка продолжится. Разрешите уведомления, чтобы узнать о готовности моделей. Не закрывайте приложение смахиванием из списка недавних."))
                        .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                    #else
                    Text(L10n.text("Можно свернуть окно: загрузка продолжится. Разрешите уведомления, чтобы узнать о готовности моделей."))
                        .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                    #endif
                    if let error = packages.errors["downloadSpace"] { Text(error).foregroundStyle(.orange) }
                    if started {
                        if packages.downloadingAll { Text(L10n.text("Скачиваю выбранные пакеты…")).font(AppPlatform.panelCaption) }
                        else if complete { Label(L10n.text("Пакеты для перевода готовы"), systemImage: "checkmark.circle") }
                        else { Text(L10n.text("Загрузка не завершена. Проверьте подключение и продолжите скачивание.")).foregroundStyle(.orange) }
                    }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    // Room below the last control, so the bottom bar never rests on a toggle.
                    .padding(.bottom, 24)
            }
            .katScreenSurface().navigationTitle(L10n.text("Ваши языки")).katInlineTitle()
            .katDoneToolbar(L10n.text("Позже"), enabled: !applying) { dismiss() }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if started {
                        let progress = packages.setupProgress(setup, model: choice)
                        CatDownloadProgressView(value: Double(progress.received), total: Double(progress.total), isActive: packages.downloadingAll && progress.status == .downloading)
                    }
                    Text(!packages.restored ? L10n.text("Проверяю модели…") : alreadyInstalled ? L10n.text("Всё нужное уже скачано") : L10n.text("Осталось скачать: ") + size(bytes)).font(AppPlatform.panelHeading).accessibilityIdentifier("setup.bytes")
                    Text(L10n.text("Уже установленные файлы не скачиваются повторно."))
                        .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                    if packages.downloadingAll {
                        Button(L10n.text("Приостановить скачивание")) { Task { await packages.pauseAll() } }
                    } else if alreadyInstalled {
                        // Nothing to download: Download stays inactive, Done saves the language choice.
                        // Same shape and width for both, so the inactive Download does not read as plain text.
                        HStack(spacing: 12) {
                            Button {} label: { Text(L10n.text("Скачать")).frame(minWidth: 110) }
                                .buttonStyle(.borderedProminent).foregroundStyle(Color.gray).fontWeight(.semibold)
                                .disabled(true).accessibilityIdentifier("setup.download")
                            Button { Task { await finish() } } label: { Text(L10n.text("Готово")).frame(minWidth: 110) }
                                .buttonStyle(.borderedProminent).foregroundStyle(Color.black).fontWeight(.semibold)
                                .disabled(!setup.isValid || applying || probe == nil)
                                .accessibilityIdentifier("setup.done")
                        }
                    } else {
                        DownloadButton(complete && started ? L10n.text("Готово") : L10n.text("Скачать"), items: complete && started ? [] : packages.setupDownloadFiles(setup, model: choice)) {
                            if started && complete { dismiss(); Task { await model.applyAutoTranslation(); await model.loadAutomaticallyIfNeeded() } }
                            else { Task { await begin() } }
                        }.buttonStyle(.borderedProminent).foregroundStyle(!setup.isValid || !packages.restored || applying ? Color.gray : Color.black).fontWeight(.semibold)
                            .disabled(!setup.isValid || !packages.restored || applying || probe == nil)
                            .accessibilityIdentifier("setup.download")
                    }
                    CancelDownloadBatchButton(model: model, packages: packages)
                    if let error = packages.errors["downloadBatch"] { Text(error).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity).padding().background(AppPlatform.badgeBackground)
                    .overlay(alignment: .top) { Divider() }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("setup.bar")
            }
        }.disabled(packages.cancellingBatch)
        .task { if probe == nil { await runProbe() } }
        .katSheetClose(enabled: !applying, identifier: "setup.close") { dismiss() }.interactiveDismissDisabled(packages.downloadingAll).preferredColorScheme(.dark).tint(KatTheme.accent)
    }
    /// Step 1: 3–5 s memory and GPU check before languages, so the plan fits this device.
    private var deviceCheck: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Проверка устройства")).font(AppPlatform.panelHeading)
            if let probe, !probing {
                let cpu = String(format: "%.0f", probe.cpuGbps), gpu = String(format: "%.0f", probe.gpuGbps), speed = String(format: "%.1f", probe.estimate9B)
                Text(L10n.text("Память: \(cpu) ГБ/с · GPU: \(gpu) ГБ/с · Index 9B: ~\(speed) ток/с"))
                    .font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                Text(probe.strong ? L10n.text("Рекомендуем: Index 9B — одна модель на все языки, лучшее качество.")
                     : L10n.text("Рекомендуем: OPUS для поддерживаемых пар + Index 2B для остальных — быстрее на этом устройстве."))
                    .font(AppPlatform.panelBody).foregroundStyle(KatTheme.accent).accessibilityIdentifier("setup.recommendation")
                Button(L10n.text("Проверить снова")) { Task { await runProbe() } }.disabled(started || applying).accessibilityIdentifier("setup.probe")
            } else {
                ProgressView()
                Text(L10n.text("Проверяю память и графический процессор, 3–5 секунд. Ничего не скачивается.")).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
    private func runProbe() async { probing = true; probe = await DeviceProbe.run(); probing = false }
    private func names(_ values: [SpeechLanguage]) -> String { values.map { TranslationLanguage.name($0.rawValue) }.joined(separator: ", ") }
    private func languageColumn(primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(primary ? L10n.text("Основной язык") : L10n.text("Языки перевода")).font(AppPlatform.panelBody.weight(.semibold))
            TextField(L10n.text("Поиск языка"), text: primary ? $primarySearch : $targetSearch)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled().font(AppPlatform.panelBody)
                .focused($focusedColumn, equals: primary ? 0 : 1)
                .accessibilityIdentifier(primary ? "setup.search.primary" : "setup.search.targets")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(TranslationLanguage.catalog.filter { item in item.available && TranslationModel.selectable.contains(where: { item.connected(to: $0) }) }.filter { $0.matches(primary ? primarySearch : targetSearch) && (primary || $0.id != setup.primaryID) }) { item in
                        Button {
                            focusedColumn = nil
                            if primary { setup.primaryID = item.id; setup.targetIDs.removeAll { $0 == item.id } }
                            else if setup.targetIDs.contains(item.id) { setup.targetIDs.removeAll { $0 == item.id } }
                            else { setup.targetIDs.append(item.id) }
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.displayName).font(AppPlatform.panelBody).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if primary ? setup.primaryID == item.id : setup.targetIDs.contains(item.id) { Image(systemName: "checkmark.circle.fill") }
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier((primary ? "setup.primary." : "setup.target.") + item.id)
                        Divider()
                    }
                }
            }.frame(height: 230)
        }.frame(maxWidth: .infinity)
    }
    /// The plan is ready before any download (all files installed and the user has not started one).
    private var alreadyInstalled: Bool { packages.restored && !started && complete }
    private func finish() async {
        guard await apply() else { return }
        dismiss(); await model.applyAutoTranslation(); await model.loadAutomaticallyIfNeeded()
    }
    private func begin() async {
        guard await apply() else { return }
        started = true
        packages.startAll()
    }
    @discardableResult private func apply() async -> Bool {
        guard setup.isValid, !applying else { return false }
        applying = true
        defer { applying = false }
        if !packages.autoTranslation { await model.selectTranslation(choice) }
        packages.saveLanguageSetup(setup)
        model.languages = LanguageSelection(sourceID: setup.primaryID, targetID: setup.languages.first { $0.rawValue != setup.primaryID }!.rawValue, automaticRequested: false)
        UserDefaults.standard.set(true, forKey: "languageSetupCompleted")
        return true
    }
}
