import SwiftUI
import OfflineCore
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Bindable private var interfaceLanguage = AppInterfaceLanguage.shared
    @AppStorage("recognitionPreference") private var recognitionPreference: RecognitionPreference = .automatic
    @AppStorage("recordingMode") private var mode: RecordingMode = .toggle
    @AppStorage("recordingSilenceSeconds") private var silenceSeconds = SilenceMonitor.defaultTimeout
    @AppStorage("recordingLimitMinutes") private var limitMinutes = RecordingPolicy.defaultMinutes
    @AppStorage("whisperDateTimeRepair") private var dateTimeRepair = WhisperDateTimeRepair.defaultEnabled
    @AppStorage("recordingPreprocessing") private var preprocessing = true
    @AppStorage("recordingPreviewVerification") private var verification = true
    #if os(macOS)
    @AppStorage("macTranslationIdleMinutes") private var translationIdleMinutes = 5.0
    @AppStorage("macExperimentalTranslationGlossary") private var experimentalGlossary = false
    @AppStorage("macExperimentalTranslationChunks") private var experimentalChunks = true
    #endif
    @AppStorage("memorySaving") private var memorySaving = false
    @AppStorage("automaticModelLoad") private var automaticModelLoad = true
    @AppStorage("historyRecordText") private var recordText = true
    @AppStorage("historyRecordAudio") private var recordAudio = true
    @AppStorage("historyRecordImages") private var recordImages = true
    @AppStorage("showTechnicalInfo") private var showTechnicalInfo = false
    @State private var showRecognitionModels = false
    @State private var confirmClear = false
    @State private var clearing = false
    @State private var clearMessage: String?
    @State private var versionCopied = false
    @State private var versionCopyID = UUID()
    @AppStorage("historyTextCount") private var textCount = 100
    @AppStorage("historyAudioCount") private var audioCount = 10
    @AppStorage("historyImageCount") private var imageCount = 20
    @AppStorage("historyImageDays") private var imageDays = 30.0
    @AppStorage("historyTextDays") private var textDays = 30.0
    @AppStorage("historyAudioDays") private var audioDays = 30.0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.text("Язык приложения"), selection: $interfaceLanguage.preference) {
                        Text(L10n.text("Как в системе")).tag("system")
                        Text(L10n.text("Русский")).tag("ru")
                        Text("English").tag("en")
                        Text("Español").tag("es")
                        Text("Türkçe").tag("tr")
                    }.pickerStyle(.menu).accessibilityIdentifier("settings.interfaceLanguage")
                }
                #if os(macOS)
                Section {
                    NavigationLink(L10n.text("Горячие клавиши")) { HotkeySettingsView() }
                        .accessibilityIdentifier("settings.shortcuts")
                }
                #endif
                Section {
                    Picker(L10n.text("Кнопка микрофона"), selection: $mode) {
                        Text(L10n.text("Удерживать для записи")).tag(RecordingMode.hold)
                        Text(L10n.text("Нажать для старта / остановки")).tag(RecordingMode.toggle)
                    }.katRecordingPicker().accessibilityIdentifier("settings.recordingMode")
                    LabeledContent(L10n.text("Остановка после тишины"), value: L10n.text("\(Int(silenceSeconds)) с"))
                    Slider(value: $silenceSeconds, in: 1...30, step: 1).accessibilityLabel(L10n.text("Тишина до остановки записи в секундах"))
                    Stepper(value: $limitMinutes, in: 1...RecordingPolicy.maximumMinutes, step: 1) {
                        LabeledContent(L10n.text("Лимит записи"), value: L10n.text("\(RecordingPolicy.limitSeconds(minutes: limitMinutes) / 60) мин"))
                            .accessibilityElement(children: .ignore).accessibilityLabel(L10n.text("Лимит записи"))
                            .accessibilityValue(L10n.text("\(RecordingPolicy.limitSeconds(minutes: limitMinutes) / 60) мин"))
                            .accessibilityIdentifier("recording.limit.value")
                    }.accessibilityIdentifier("recording.limit.stepper")
                } header: {
                    SettingsSectionHeader(L10n.text("Управление записью"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Запись остановится по лимиту или после выбранной паузы без речи. Настройки сохраняются сразу и действуют со следующей записи."))
                    }
                }
                Section {
                    ForEach(RecognitionPreference.allCases, id: \.self) { choice in
                        Button {
                            recognitionPreference = choice
                            model.objectWillChange.send()
                        } label: {
                            HStack {
                                Text(recognitionTitle(choice)).foregroundStyle(.primary)
                                Spacer()
                                if recognitionPreference == choice {
                                    Image(systemName: "checkmark").foregroundStyle(KatTheme.accent)
                                }
                            }.frame(minHeight: 28).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("settings.recognition." + choice.rawValue)
                            .accessibilityAddTraits(recognitionPreference == choice ? .isSelected : [])
                    }
                    Button(L10n.text("Модели распознавания")) { showRecognitionModels = true }
                } header: {
                    SettingsSectionHeader(L10n.text("Распознавание речи"))
                } footer: {
                    Text(L10n.text("Авто выбирает распознаватель по языку. В ручном режиме используется только выбранный движок; его пакет нужно скачать в разделе моделей. Выбор применяется со следующей записи и не меняет модель перевода."))
                    if recognitionPreference == .ultra {
                        Text(L10n.text("Ultra поддерживает 25 языков, включая русский и английский. Для остальных выберите Авто или Whisper."))
                    }
                    if let issue = model.voiceLanguageIssue { Text(issue) }
                }
                Section {
                    Toggle(L10n.text("Исправлять дату и время"), isOn: $dateTimeRepair)
                        .accessibilityIdentifier("settings.whisperDateTimeRepair")
                } footer: {
                    Text(L10n.text("Whisper повторно проверяет неоднозначные дату и время в русской речи. Может увеличить ожидание."))
                }
                #if os(macOS)
                Section {
                    Toggle(L10n.text("Переводить по частям"), isOn: $experimentalChunks)
                        .accessibilityIdentifier("settings.translationChunks")
                        .onChange(of: experimentalChunks) { _, enabled in model.session.showsTranslationPartials = enabled }
                    Text(L10n.text("Только Index 9B. Первые части могут появляться раньше, но контекст между ними может теряться, а полный перевод — занимать больше времени. Применяется к следующему переводу."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Toggle(L10n.text("Автоматический словарь терминов"), isOn: $experimentalGlossary)
                        .accessibilityIdentifier("settings.translationGlossary")
                } header: {
                    SettingsSectionHeader(L10n.text("Экспериментально"))
                } footer: {
                    Text(L10n.text("Только Index 9B, с русского на английский. Подбирает общие термины для частей текста и изображения. Добавляет ожидание перед переводом и может ошибаться. Применяется к следующему переводу."))
                }
                #endif
                Section {
                    Toggle(L10n.text("Переводить во время записи"), isOn: $preprocessing)
                        .accessibilityIdentifier("settings.recordingPreprocessing")
                    if preprocessing {
                        Toggle(L10n.text("Проверять текст после записи"), isOn: $verification)
                            .accessibilityIdentifier("settings.recordingPreviewVerification")
                    }
                } header: {
                    SettingsSectionHeader(L10n.text("Экспериментально"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Оригинал и перевод законченных фраз появляются во время записи. Озвучка начнётся после остановки. Для Whisper с Index без экономии памяти. Экспериментальный режим: возможны пропуски, повторы и ошибки распознавания."))
                        if preprocessing {
                            Text(L10n.text("Проверка повторно распознаёт запись и обновляет изменившиеся фразы перед озвучкой. Увеличивает ожидание и не гарантирует точность перевода."))
                        }
                    }
                }
                Section {
                    NavigationLink(L10n.text("Голоса и образцы")) { VoiceSettingsView(model: model) }
                } header: {
                    SettingsSectionHeader(L10n.text("Озвучка"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Образцы доступны до скачивания и смены голоса."))
                    }
                }
                Section {
                    Toggle(L10n.text("Загружать модель при запуске"), isOn: $automaticModelLoad)
                        .accessibilityIdentifier("settings.automaticModelLoad")
                    #if os(macOS)
                    Stepper(value: $translationIdleMinutes, in: 1...60, step: 1) {
                        LabeledContent(L10n.text("Выгружать переводчик после простоя"), value: L10n.text("\(Int(translationIdleMinutes)) мин"))
                    }.accessibilityIdentifier("settings.translationIdleMinutes").disabled(memorySaving)
                    #endif
                    Toggle(L10n.text("Экономия памяти"), isOn: $memorySaving)
                        .onChange(of: memorySaving) { _, _ in Task { await model.unload() } }
                } header: {
                    SettingsSectionHeader(L10n.text("Память"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Подготовить выбранную скачанную модель при открытии приложения. В режиме экономии памяти перевод загружается только перед запросом."))
                        #if os(macOS)
                        Text(L10n.text("Модель перевода остаётся в памяти между запросами. После простоя она выгружается и автоматически загружается при следующем переводе. Экономия памяти выгружает её сразу после этапа перевода."))
                        #endif
                        Text(L10n.text("Выгружать модели между этапами. Меньше расход памяти, но больше ожидание загрузки."))
                    }
                }
                Section {
                    Toggle(L10n.text("Сохранять текст переводов"), isOn: $recordText).accessibilityIdentifier("history.recordText")
                        .onChange(of: recordText) { _, _ in Task { await model.history.applyRecordingSettings() } }
                    countPicker(L10n.text("Хранить переводов"), value: $textCount)
                    Text(textDays == 0 ? L10n.text("Не удалять по возрасту") : L10n.retentionDays(Int(textDays)))
                    Slider(value: $textDays, in: 0...365, step: 1).accessibilityLabel(L10n.text("Срок хранения текста в днях"))
                } header: {
                    SettingsSectionHeader(L10n.text("Текстовая история"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Если отключить, новый текст не попадёт в историю. Сохранённые записи останутся."))
                    }
                }
                Section {
                    Toggle(L10n.text("Сохранять аудио переводов"), isOn: $recordAudio).accessibilityIdentifier("history.recordAudio")
                        .onChange(of: recordAudio) { _, _ in Task { await model.history.applyRecordingSettings() } }
                    countPicker(L10n.text("Хранить аудиофайлов"), value: $audioCount)
                    Text(audioDays == 0 ? L10n.text("Не удалять по возрасту") : L10n.retentionDays(Int(audioDays)))
                    Slider(value: $audioDays, in: 0...365, step: 1).accessibilityLabel(L10n.text("Срок хранения аудио в днях"))
                } header: {
                    SettingsSectionHeader(L10n.text("Озвученные переводы"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Отключение сохранения не мешает озвучке. Ранее сохранённые аудиофайлы останутся. При включённом сохранении аудио сохраняются и исходные записи речи."))
                    }
                }
                Section {
                    Toggle(L10n.text("Сохранять изображения с переводом"), isOn: $recordImages).accessibilityIdentifier("history.recordImages")
                        .onChange(of: recordImages) { _, _ in Task { await model.history.applyRecordingSettings() } }
                    countPicker(L10n.text("Хранить изображений"), value: $imageCount)
                    Text(imageDays == 0 ? L10n.text("Не удалять по возрасту") : L10n.retentionDays(Int(imageDays)))
                    Slider(value: $imageDays, in: 0...365, step: 1).accessibilityLabel(L10n.text("Срок хранения изображений в днях"))
                } header: {
                    SettingsSectionHeader(L10n.text("Изображения с переводом"))
                } footer: {
                    Text(L10n.text("Готовые изображения сохраняются после перевода. Исходные файлы не изменяются. Хранение картинок и распознанного текста настраивается отдельно."))
                }
                Section {
                    Text(L10n.text("Настройки сохраняются автоматически. Очистка по новым лимитам выполняется при закрытии настроек. 0 дней отключает удаление по возрасту."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button(L10n.text("Очистить историю"), role: .destructive) { confirmClear = true }
                        .accessibilityIdentifier("history.clear").disabled(clearing)
                    if clearing { ProgressView(L10n.text("Удаляю историю…")) }
                    if let clearMessage { Text(clearMessage).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
                    Text(L10n.text("Удалить все сохранённые переводы, аудиофайлы и изображения. Настройки сохранения останутся прежними."))
                }
                Section {
                    Toggle(L10n.text("Показывать диагностику"), isOn: $showTechnicalInfo)
                        .accessibilityIdentifier("settings.showTechnicalInfo")
                } header: {
                    SettingsSectionHeader(L10n.text("Интерфейс"))
                } footer: {
                    Text(L10n.text("Показывать на главном экране значок с расходом памяти и времени обработки."))
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kat translator").font(.headline)
                        Text(L10n.text("Офлайн-переводчик голоса, текста и изображений. ИИ-модели работают на вашем iPhone после скачивания нужных пакетов."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    versionInformation
                    NavigationLink(L10n.text("Определение языка — лицензии")) {
                        ScrollView {
                            Text(TextLanguageDetection.attribution).font(AppPlatform.panelBody)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        }.navigationTitle(L10n.text("Определение языка — лицензии"))
                    }
                    NavigationLink(L10n.text("Конфиденциальность и точность")) { PrivacyView() }
                        .accessibilityIdentifier("settings.privacy")
                } header: {
                    SettingsSectionHeader(L10n.text("О приложении"))
                }
            }
                .sheet(isPresented: $showRecognitionModels) {
                    ModelsView(coordinator: model.packages, session: model.session, model: model) { await model.removeModel($0) }
                }
                .katSectionSpacing().katDesktopPanelSurface()
                .navigationTitle(L10n.text("Настройки"))
                .alert(L10n.text("Очистить всю историю?"), isPresented: $confirmClear) {
                    Button(L10n.text("Удалить весь текст и аудио"), role: .destructive) {
                        clearing = true; clearMessage = nil
                        Task {
                            await model.history.clear()
                            clearMessage = model.history.error.map { L10n.text("Не удалось полностью очистить историю: ") + $0 } ?? L10n.text("История очищена")
                            clearing = false
                        }
                    }
                    Button(L10n.text("Отмена"), role: .cancel) {}
                } message: { Text(L10n.text("Все записи истории будут удалены без возможности восстановления.")) }
                .katDoneToolbar { saveRetention(); dismiss() }
        }.environment(\.locale, L10n.locale)
            .katSheetClose(identifier: "settings.close", maxWidth: 860) { saveRetention(); dismiss() }
            .onDisappear { saveRetention() } // swipe-dismissed sheet; Mac Settings window closed from its title bar
    }
    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var appBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    private var versionInformation: some View {
        Button {
            var information = "Kat translator\n" + L10n.text("Версия") + ": " + appVersion + "\n" + L10n.text("Сборка") + ": " + appBuild
            if let identifier = AppBuildInformation.identifier { information += "\n" + L10n.text("ID сборки") + ": " + identifier }
            AppClipboard.copy(information)
            versionCopied = true; versionCopyID = UUID()
        } label: {
            HStack(spacing: 16) {
                VStack(spacing: 10) {
                    LabeledContent(L10n.text("Версия"), value: appVersion).accessibilityIdentifier("settings.version")
                    LabeledContent(L10n.text("Сборка"), value: appBuild).accessibilityIdentifier("settings.build")
                    if let identifier = AppBuildInformation.identifier {
                        LabeledContent(L10n.text("ID сборки")) {
                            Text(identifier).monospaced().textSelection(.disabled)
                        }.accessibilityIdentifier("settings.buildID")
                    }
                }.foregroundStyle(.primary)
                Image(systemName: versionCopied ? "checkmark" : "doc.on.doc").foregroundStyle(KatTheme.accent)
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("settings.copyVersion")
            .accessibilityLabel(L10n.text("Скопировать версию и сборку"))
            .accessibilityValue(versionCopied ? L10n.text("Скопировано") : appVersion + " (" + appBuild + ") " + (AppBuildInformation.identifier ?? ""))
            .task(id: versionCopyID) {
                guard versionCopied else { return }
                do { try await Task.sleep(for: .seconds(3)); versionCopied = false } catch {}
            }
    }
    private func recognitionTitle(_ preference: RecognitionPreference) -> String {
        switch preference {
        case .automatic: return L10n.text("Авто")
        case .ultra: return "Parakeet Ultra"
        case .whisper: return L10n.text("Whisper (классический)")
        }
    }
    @ViewBuilder private func countPicker(_ title: String, value: Binding<Int>) -> some View {
        #if os(macOS)
        HStack(spacing: 12) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 16)
            TextField(title, value: value, format: .number)
                .labelsHidden().textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).frame(width: 90)
                .accessibilityIdentifier(title == L10n.text("Хранить переводов") ? "settings.textCount" : title == L10n.text("Хранить изображений") ? "settings.imageCount" : "settings.audioCount")
            Stepper(title, value: value, in: 0...10000).labelsHidden().fixedSize()
        }
        if value.wrappedValue == 0 { Text(L10n.text("Без ограничения")).font(.caption).foregroundStyle(.secondary) }
        #else
        VStack(alignment: .leading) {
            HStack {
                Text(title); Spacer()
                TextField(title, value: value, format: .number).katNumberInput().multilineTextAlignment(.trailing).frame(width: 80)
            }
            Stepper(value.wrappedValue == 0 ? L10n.text("Без ограничения") : L10n.text("Последние \(value.wrappedValue)"), value: value, in: 0...10000)
        }
        #endif
    }

    private func saveRetention() {
        // AppStorage persists edits immediately. Defer pruning until editing ends
        // so an intermediate number entered in a text field cannot delete history.
        Task { await model.history.confirmPolicy() }
    }
}

/// Native grouped-section heading, visually separate from controls and help text.
struct SettingsSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}
