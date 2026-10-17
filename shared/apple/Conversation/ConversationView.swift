import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import OfflineCore
private enum TranslatorInput: String, CaseIterable { case voice, text, camera }
private enum ReadingField { case voiceOriginal, voiceTranslation, textOriginal, textTranslation
    #if os(macOS)
    case imageTranslation
    #endif
    var original: Bool { self == .voiceOriginal || self == .textOriginal }
}
struct ConversationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var session: ConversationPipeline
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var packages: PackageDownloadCoordinator
    @ObservedObject var history: HistoryModel
    #if os(macOS)
    @ObservedObject private var imageModel: CameraModel
    @ObservedObject private var imageTranslation: ImageTranslationSession
    @ObservedObject private var integration: MacIntegration
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    #endif
    @AppStorage("recordingMode") private var recordingMode: RecordingMode = .toggle
    @AppStorage("automaticSpeechVoice") private var automaticSpeechVoice = true
    @AppStorage("automaticSpeechText") private var automaticSpeechText = false
    @AppStorage("showTechnicalInfo") private var showTechnicalInfo = false
    @State private var input: TranslatorInput = .voice
    @State private var previousInput: TranslatorInput = .voice
    @State private var showModels = false
    @State private var showHistory = false
    @State private var showAudioImporter = false
    @State private var showSettings = false
    @State private var showMetrics = false
    @State private var typedText = ""
    @State private var desktopEditorHeight: CGFloat = 340
    @FocusState private var editingText: Bool
    @State private var speakingField: String?
    @State private var showReport = false
    @State private var originalExpanded = AppPlatform.expandOriginal
    @State private var voiceResultRevealed = false
    @State private var voiceHeaderHeight: CGFloat = 220
    @State private var voiceReadingScroll = VoiceReadingScrollState()
    @State private var voiceScrollInteracting = false
    @State private var readingField: ReadingField?
    init(model: AppModel) {
        self.model = model; session = model.session; recorder = model.recorder; packages = model.packages; history = model.history
        #if os(macOS)
        imageModel = model.camera; imageTranslation = model.camera.translation; integration = model.integration
        #endif
    }
    private let accent = KatTheme.accent
    private var cameraActivationID: String {
        #if os(macOS)
        input.rawValue + "-" + String(model.screenImageRequestID) + "-" + String(integration.textRequestID)
        #else
        input.rawValue
        #endif
    }
    private var externalTextBusy: Bool {
        #if os(macOS)
        integration.working
        #else
        false
        #endif
    }
    private var speechBusy: Bool { externalTextBusy || session.isBusy || recorder.isRecording || recorder.starting || model.preparingRecording || model.importingAudio || model.finishing || model.changingTranslation }
    private var busy: Bool { speechBusy || model.usingCamera }
    private var configurationBusy: Bool {
        #if os(macOS)
        // The Image tab stays open while idle. Lock configuration only during work.
        speechBusy || imageModel.opening || imageModel.recognizing || imageTranslation.working
        #else
        busy
        #endif
    }
    // Model preparation is shared by Voice/Text and may continue while navigating.
    // Only an active recording/translation or a model change locks the mode picker.
    private var desktopModeSwitchDisabled: Bool {
        externalTextBusy || recorder.isRecording || recorder.starting || model.preparingRecording || model.importingAudio || model.finishing || model.changingTranslation || (session.isBusy && session.isReady && !session.isPreparingRecognition)
    }
    private var showWizard: Bool {
        session.isReady && !session.isPreparingRecognition && (externalTextBusy || session.isBusy || model.finishing || model.importingAudio) && (!session.isSpeaking || session.isWaitingForSpeech) && (!recorder.isRecording || model.finishing) && !recorder.starting && !model.preparingRecording
    }
    private var showProcessingOverlay: Bool {
        input != .camera && session.activeMode != .quick && showWizard && !session.isSpeaking
    }
    private var preparingModels: Bool { !packages.restored || (!session.isReady && busy) }
    private var fields: ConversationFields { session.fields(for: input == .text ? .text : .voice) }
    private var textSource: SpeechLanguage? {
        if model.languages.automaticActive(in: .text) { return TextLanguageDetection.detect(typedText) }
        return model.languages.runtimeSource
    }
    private var status: String {
        if model.importingAudio && !session.isBusy { return L10n.text("Читаю аудиофайл…") }
        if model.finishing && recorder.isRecording { return L10n.text("Завершаю запись…") }
        if model.preparingRecording { return L10n.text("Включаю микрофон…") }
        if recorder.isRecording { return recorder.isPaused ? L10n.text("Запись на паузе") : L10n.text("Слушаю…") }
        if recorder.starting { return L10n.text("Включаю микрофон…") }
        if session.isSpeechPaused { return L10n.text("Озвучка на паузе") }
        if !session.stage.isEmpty { return session.stage }
        return session.isReady ? L10n.text("Готов к переводу") : L10n.text("Подготовим перевод")
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(macOS)
                ViewThatFits(in: .horizontal) {
                    ZStack {
                        desktopModePicker
                        HStack { if input != .camera { automaticSpeechControl.fixedSize() }; Spacer() }
                    }.frame(minWidth: 920)
                    HStack(spacing: 16) {
                        if input != .camera { automaticSpeechControl.fixedSize() }
                        Spacer(minLength: 0)
                        desktopModePicker
                    }
                }.padding(.horizontal, 20).padding(.vertical, 12)
                if let message = integration.message {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).foregroundStyle(.orange).textSelection(.enabled).accessibilityIdentifier("integration.message")
                        if integration.needsAccessibility { Button(L10n.text("Разрешить доступ к выделенному тексту…"), action: integration.requestAccessibility) }
                        if integration.needsScreenCapture { Button(L10n.text("Разрешить запись экрана…"), action: integration.requestScreenCapture) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                }
                #else
                Picker(L10n.text("Способ перевода"), selection: $input) {
                    Text(L10n.text("Голос")).tag(TranslatorInput.voice)
                    Text(L10n.text("Текст")).tag(TranslatorInput.text)
                    Text(AppPlatform.imageModeTitle).tag(TranslatorInput.camera)
                }.pickerStyle(.segmented).katModePicker().disabled(desktopModeSwitchDisabled).padding(.horizontal, 20).padding(.vertical, 10)
                #endif
                if showTechnicalInfo {
                    Text(L10n.text("Модель: ") + packages.selectedTranslation.title)
                        .font(AppPlatform.secondaryFont).foregroundStyle(.secondary).accessibilityIdentifier("model.current")
                }
                if input == .camera {
                    #if os(macOS)
                    CameraView(app: model, expandTranslation: { readingField = .imageTranslation }).withClose { input = previousInput }
                    #else
                    Color.black
                    #endif
                } else if preparingModels {
                    GeometryReader { area in
                        ScrollView {
                            ModelPreparationView(checking: !packages.restored,
                                status: !packages.restored ? L10n.text("Проверяю модели…") : status,
                                canCancel: session.isBusy || model.importingAudio || externalTextBusy, cancel: model.cancel, availableSize: area.size)
                                .frame(maxWidth: .infinity).frame(minHeight: area.size.height)
                                .background(KatTheme.background)
                        }.scrollContentBackground(.hidden).background(KatTheme.background)
                    }.background(KatTheme.background)
                } else {
                if input == .voice { voiceWorkspace }
                else { translationScrollContent }
                }
            }.background(KatTheme.background)
                .environment(\.locale, L10n.locale)
                #if os(iOS)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if input == .text && !preparingModels && !showProcessingOverlay {
                    VStack(spacing: 0) {
                        if let progress = session.translationProgress,
                           (input == .text && session.activeMode == .text) || (input == .voice && session.activeMode == .voice) {
                            TranslationProgressPanel(progress: progress)
                        }
                        textControls
                    }
                    }
                }
                #endif
                .navigationTitle("Kat translator").katInlineTitle()
                .toolbar {
                    if showTechnicalInfo {
                        Button { showReport = true } label: { Image(systemName: "chart.bar.xaxis").katToolbarIcon() }
                            .accessibilityLabel(L10n.text("Отчёт и измерения"))
                            .accessibilityIdentifier("toolbar.diagnostics")
                    }
                    Button { showHistory = true } label: { Image(systemName: "clock").katToolbarIcon() }.accessibilityLabel(L10n.text("История переводов")).accessibilityIdentifier("toolbar.history").disabled(speechBusy)
                    Button { showSettings = true } label: { Image(systemName: "gearshape").katToolbarIcon() }.accessibilityLabel(L10n.text("Настройки")).disabled(configurationBusy)
                    Button { showModels = true } label: { Image(systemName: "square.stack.3d.up").katToolbarIcon() }.accessibilityLabel(L10n.text("Модели")).disabled(configurationBusy)
                }
                .onChange(of: input) { old, new in
                    if new == .camera { previousInput = old }
                    model.selectInputMode(new == .camera ? nil : (new == .voice ? .voice : .text))
                }
                #if os(iOS)
                .katFullScreenCover(isPresented: Binding(get: { input == .camera }, set: { if !$0 { input = previousInput } })) {
                    CameraView(app: model).withClose { input = previousInput }
                }
                #endif
                .task(id: cameraActivationID) {
                    model.selectInputMode(input == .camera ? nil : (input == .voice ? .voice : .text))
                    #if os(macOS)
                    if integration.working {
                        if input == .text { await model.synchronizeRecognition(); integration.activateRequestedText() }
                        return
                    }
                    if model.importingScreenImage {
                        if input == .camera { model.activateRequestedScreenImage() }
                        return
                    }
                    #endif
                    if input == .camera { await model.openCamera() }
                    else {
                        await model.closeCamera(resumingConversation: true)
                        guard !Task.isCancelled else { return }
                        await model.synchronizeRecognition()
                    }
                }
                .sheet(isPresented: $showReport) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ResourceDiagnosticsView()
                                #if os(macOS)
                                DiagnosticsCard(L10n.text("Измерения")) { measurementValues }
                                #else
                                Divider(); metrics
                                #endif
                            }.frame(maxWidth: 900, alignment: .leading).padding(20).frame(maxWidth: .infinity)
                        }.katDesktopPanelSurface().katPanelTypography()
                            .navigationTitle(L10n.text("Диагностика"))
                            .katDoneToolbar { showReport = false }
                    }.katSheetClose(identifier: "diagnostics.close") { showReport = false }
                }
                .sheet(isPresented: $showSettings, onDismiss: {
                    Task { await model.history.refresh(); await resumeImageAfterConfiguration() }
                }) { SettingsView(model: model) }
                .sheet(isPresented: $showHistory) { HistoryView(history: history) }
                #if os(macOS)
                .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first { Task { await model.importAudioFile(url) } }
                    case .failure(let error):
                        if (error as NSError).code != NSUserCancelledError { model.message = AudioFileImportError.unreadable.localizedDescription }
                    }
                }
                #endif
                .katFullScreenCover(isPresented: $model.showLanguageSetup, onDismiss: { Task { await model.loadAutomaticallyIfNeeded() } }) { LanguageSetupView(model: model) }
                .onChange(of: packages.downloadingAll) { _, downloading in if !downloading { Task { await model.loadAutomaticallyIfNeeded() } } }
                .onOpenURL { url in if url.scheme == "kattranslator", url.host == "downloads" { showModels = true } }
                .sheet(isPresented: $showModels, onDismiss: {
                    Task { await resumeImageAfterConfiguration() }
                }) { ModelsView(coordinator: packages, session: session, model: model) { await model.removeModel($0) } }
        }.preferredColorScheme(.dark).tint(accent).katDesktopControls()
        .disabled(showProcessingOverlay)
        .accessibilityHidden(showProcessingOverlay)
        .overlay {
            if showProcessingOverlay {
                ProcessingOverlay(status: status, progress: session.translationProgress, cancel: model.cancel)
            }
        }
        #if os(macOS)
        .disabled(model.externalOperation && !integration.working)
        .onChange(of: integration.textRequestID, initial: true) { _, value in
            if value > 0 && integration.working {
                typedText = integration.text; input = .text; readingField = nil; editingText = false
                showSettings = false; showModels = false; showHistory = false; showReport = false
            }
        }
        .onReceive(permissionTimer) { _ in integration.refreshPermissions() }
        .onChange(of: model.screenImageRequestID, initial: true) { _, value in
            if value > 0 && model.importingScreenImage && input != .camera {
                input = .camera
            }
        }
        #endif
        .onChange(of: showProcessingOverlay) { _, visible in
            if visible { editingText = false }
        }
        .katTextReader(isPresented: Binding(get: { readingField != nil }, set: { if !$0 { readingField = nil } })) {
            TextReadingView(text: readingText, original: readingField?.original == true) { readingField = nil }
        }
        #if os(macOS)
        .onGeometryChange(for: CGFloat.self) { max(300, $0.size.height - 390) } action: { desktopEditorHeight = $0 }
        #endif
    }
    private func resumeImageAfterConfiguration() async {
        #if os(macOS)
        // Selecting/removing a model closes its Image runtime. Rebind the current
        // selection without clearing the visible image or loading it eagerly.
        if input == .camera { await model.openCamera() }
        #endif
        if input != .camera { await model.synchronizeRecognition() }
    }
    private var automaticSpeechControl: some View {
        Toggle(L10n.text("Автоматически озвучивать"), isOn: input == .voice ? $automaticSpeechVoice : $automaticSpeechText)
            .disabled(busy || !packages.canSpeak(model.languages.runtimeTarget ?? .english))
            .accessibilityIdentifier("language.automaticSpeech")
    }
    #if os(macOS)
    private var desktopModePicker: some View {
        HStack(spacing: 4) {
            ForEach(TranslatorInput.allCases, id: \.self) { value in
                Button { input = value } label: {
                    Text(value == .voice ? L10n.text("Голос") : value == .text ? L10n.text("Текст") : AppPlatform.imageModeTitle)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(input == value ? Color.black : Color.primary)
                .background(input == value ? KatTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(input == value ? .isSelected : [])
                    .accessibilityIdentifier("mode." + value.rawValue)
            }
        }.padding(4).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .frame(width: 460).disabled(desktopModeSwitchDisabled)
    }
    #endif
    private var languageControls: some View {
        Group {
                    #if os(macOS)
                    LanguagePairPicker(selection: $model.languages, mode: input == .voice ? .voice : .text, model: packages.selectedTranslation, app: model, packages: packages, compact: true, showsDetails: false, detectedSource: input == .text ? textSource : nil).disabled(busy)
                    #else
                    LanguagePairPicker(selection: $model.languages, mode: input == .voice ? .voice : .text, model: packages.selectedTranslation, app: model, packages: packages, compact: true).disabled(busy)
                    #endif
                    if let issue = input == .voice ? model.voiceLanguageIssue : model.languageIssue {
                        Text(issue).font(.caption).foregroundStyle(.orange)
                    }
                    #if os(iOS)
                    automaticSpeechControl
                    #else
                    if input == .text { textPrimaryButton.frame(maxWidth: .infinity) }
                    if input == .text && session.isBusy && !showProcessingOverlay {
                        HStack(spacing: 12) {
                            if showWizard { CatWizardView().frame(width: 64, height: 58).accessibilityIdentifier("text.processing.cat") }
                            if let progress = session.translationProgress { TranslationProgressPanel(progress: progress) }
                            else { Text(status).font(AppPlatform.panelCaption).foregroundStyle(.secondary) }
                        }
                    }
                    #endif
                    if !packages.canSpeak(model.languages.runtimeTarget ?? .english) {
                        Text((model.languages.runtimeTarget?.hasVoice ?? false) ? L10n.text("Для озвучки скачайте голос в настройках. Перевод доступен без него.") : L10n.text("Для этого языка пока доступен перевод без озвучки.")).font(.caption).foregroundStyle(.secondary)
                    }
        }
    }
    private var notices: some View {
        Group {
                    if let message = model.message ?? fields.error { Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(.orange) }
                    if let notice = fields.speechNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if let warning = fields.archiveWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
        }
    }
    private var voiceResults: some View {
        Group {
                        if session.isRecordingPreview, !fields.translatedText.isEmpty {
                            Text(L10n.text("Предварительный перевод")).font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("recording.preview")
                        }
                        if !fields.translatedText.isEmpty {
                            voiceTranslationCard.id("voice.result")
                        }
                        if !fields.sourceText.isEmpty || session.hasOriginalRecording {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 2) {
                                    Button { originalExpanded.toggle() } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: originalExpanded ? "chevron.down" : "chevron.right")
                                            Text(L10n.text("Оригинал") + (fields.resolvedSource.map { " · " + TranslationLanguage.shortCode($0.rawValue) } ?? ""))
                                                .lineLimit(1).minimumScaleFactor(0.85)
                                        }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                        .accessibilityLabel(originalExpanded ? L10n.text("Свернуть") : L10n.text("Показать полностью"))
                                        .accessibilityIdentifier("voice.original.disclosure")
                                    ExpandTextButton(enabled: !fields.sourceText.isEmpty, identifier: "voice.original.expand") { readingField = .voiceOriginal }
                                    if session.hasOriginalRecording {
                                        Button {
                                            if session.isPlayingOriginalRecording { session.cancel() }
                                            else {
                                                history.stopPlayback(); model.voicePreview.stop()
                                                Task { await session.playOriginalRecording() }
                                            }
                                        } label: {
                                            Image(systemName: session.isPlayingOriginalRecording ? "stop.fill" : "play.fill")
                                                .frame(width: 36, height: 44)
                                        }.disabled(speechBusy && !session.isPlayingOriginalRecording)
                                            .accessibilityLabel(session.isPlayingOriginalRecording ? L10n.text("Остановить запись оригинала") : L10n.text("Воспроизвести запись оригинала"))
                                            .accessibilityIdentifier("voice.original.playback")
                                    }
                                    CopyTextButton(text: fields.sourceText, title: L10n.text("Скопировать оригинал"), iconSize: 36)
                                        .accessibilityIdentifier("voice.copy.original")
                                    if session.hasOriginalRecording {
                                        VoiceAudioShareButton(session: session)
                                            .disabled(speechBusy && !session.isPlayingOriginalRecording)
                                            .accessibilityIdentifier("voice.original.shareAudio")
                                    }
                                    Button(action: clearFields) { Image(systemName: AppPlatform.clearSymbol).frame(width: AppPlatform.clearControlSize, height: AppPlatform.clearControlSize) }.katCloseControl()
                                        .accessibilityLabel(L10n.text("Очистить оригинал"))
                                        .accessibilityIdentifier("voice.original.clear")
                                }.katDesktopIconFont()
                                if originalExpanded {
                                    Text(fields.sourceText).font(AppPlatform.voiceTextFont).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityIdentifier("voice.original.text")
                                }
                                TextCharacterCount(text: fields.sourceText, identifier: "voice.original.count")
                            }.padding(16).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        }
        }
    }
    private var translationScrollContent: some View {
                ScrollViewReader { scroll in
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    languageControls
                    if input == .text {
                        TextTranslationFields(session: session, input: $typedText, output: fields.translatedText,
                            source: textSource,
                            target: fields.resolvedTarget ?? model.languages.runtimeTarget ?? .english,
                            busy: busy, canSpeakSource: textSource.map { packages.canSpeak($0) } ?? false, canSpeakTarget: packages.canSpeak(fields.resolvedTarget ?? model.languages.runtimeTarget ?? .english), speakingField: speakingField ?? (session.isSpeaking ? "target" : nil),
                            paused: session.isSpeechPaused, speed: session.playbackSpeed,
                            pauseResume: session.toggleSpeechPause, selectSpeed: session.setPlaybackSpeed,
                            editing: $editingText,
                            clearSource: clearFields,
                            clearTarget: clearFields,
                            speak: { text, language, field in
                                editingText = false; speakingField = field
                                Task { await model.readText(text, language: language, isTranslation: field == "target"); speakingField = nil }
                            }, stop: { model.cancel() },
                            expandSource: { editingText = false; readingField = .textOriginal },
                            expandTarget: { editingText = false; readingField = .textTranslation }, editorHeight: desktopEditorHeight,
                            timing: showTechnicalInfo ? fields.timing : nil,
                            submit: { if !busy { performTextPrimaryAction() } })
                    }
                    notices
                    if input == .voice { voiceResults }

                }.padding(20)
                }.scrollDismissesKeyboard(.interactively)
                    .onChange(of: fields.translatedText) { _, text in
                        originalExpanded = AppPlatform.expandOriginal
                        if input == .voice, !text.isEmpty {
                            withAnimation { scroll.scrollTo("voice.result", anchor: .top) }
                        }
                    }
                    .onChange(of: fields.sourceText) { _, _ in originalExpanded = AppPlatform.expandOriginal }
                    .onChange(of: recorder.isRecording) { _, recording in if recording { originalExpanded = AppPlatform.expandOriginal } }
                    .onChange(of: input) { _, _ in originalExpanded = AppPlatform.expandOriginal }
                }
    }
    private var voiceShowsResults: Bool {
        VoiceResultVisibility.shouldShow(hasOriginal: !fields.sourceText.isEmpty || session.hasOriginalRecording, hasTranslation: !fields.translatedText.isEmpty,
            capturing: recorder.isRecording || recorder.starting || model.preparingRecording || model.importingAudio,
            finishing: model.finishing, processing: session.isBusy && session.activeMode == .voice,
            preview: session.isRecordingPreview, alreadyShown: voiceResultRevealed)
    }
    private var voiceWorkspace: some View {
        GeometryReader { area in
            let playbackInCard = voiceShowsResults && (session.isBusy || model.finishing)
            let hideMicrophone = showProcessingOverlay || playbackInCard || (voiceShowsResults && voiceReadingScroll.isHidden)
            let headerHeight = min(area.size.height, voiceHeaderHeight)
            let actionHeight = voiceShowsResults ? min(area.size.height, 80) : max(0, area.size.height - headerHeight)
            ZStack(alignment: .bottom) {
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 16) {
                                languageControls
                                notices
                            }.padding(20)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { voiceHeaderHeight = $0 }
                            if voiceShowsResults {
                                VStack(alignment: .leading, spacing: 20) { voiceResults }
                                    .padding(.horizontal, 20).padding(.top, 4)
                                    // End padding lets the last line scroll above the floating mic.
                                    // It does not reserve a fixed strip across the reading viewport.
                                    .padding(.bottom, 96)
                            }
                        }
                    }.frame(height: voiceShowsResults ? area.size.height : headerHeight)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .accessibilityIdentifier("voice.reading")
                        .onScrollPhaseChange { _, phase in
                            voiceScrollInteracting = phase == .interacting || phase == .decelerating
                        }
                        .onScrollGeometryChange(for: Double.self) { geometry in
                            Double(geometry.contentOffset.y + geometry.contentInsets.top)
                        } action: { _, offset in
                            voiceReadingScroll.update(offset: offset, userScrolling: voiceScrollInteracting && voiceShowsResults)
                        }
                        .onChange(of: voiceShowsResults, initial: true) { _, visible in
                            if visible && !voiceResultRevealed {
                                originalExpanded = true
                                voiceResultRevealed = true
                                voiceReadingScroll = VoiceReadingScrollState()
                                scroll.scrollTo("voice.result", anchor: .top)
                            }
                        }
                }
                // Keep the same recording control alive during the transition from
                // result to recording, including an already-held microphone gesture.
                ScrollView {
                    voiceAction(compact: voiceShowsResults, availableSize: area.size)
                        .frame(maxWidth: .infinity).frame(minHeight: actionHeight)
                }.frame(height: actionHeight)
                    .scrollDisabled(voiceShowsResults)
                    .background {
                        if voiceShowsResults {
                            LinearGradient(colors: [.clear, KatTheme.background, KatTheme.background], startPoint: .top, endPoint: .bottom)
                        }
                    }
                    .opacity(hideMicrophone ? 0 : 1)
                    .offset(y: hideMicrophone ? 16 : 0)
                    .allowsHitTesting(!hideMicrophone).accessibilityHidden(hideMicrophone)
                    .animation(.easeOut(duration: 0.18), value: hideMicrophone)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: fields.sourceText) { _, text in
                if text.isEmpty && !session.hasOriginalRecording { voiceResultRevealed = false; originalExpanded = AppPlatform.expandOriginal }
            }
            .onChange(of: recorder.starting || recorder.isRecording || model.preparingRecording || model.importingAudio) { _, active in
                if active { voiceResultRevealed = false; voiceReadingScroll = VoiceReadingScrollState() }
            }
    }
    private func voiceAction(compact: Bool, availableSize: CGSize) -> some View {
        VoiceStageControls(model: model, recordingMode: recordingMode, status: status,
                         showWizard: showWizard && !voiceResultRevealed && !showProcessingOverlay, compact: compact, availableSize: availableSize, showModels: { showModels = true }, importAudio: { showAudioImporter = true })
    }
    private func clearFields() {
        model.cancel()
        session.clearFields(in: input == .text ? .text : .voice)
        if input == .text { typedText = "" }
        model.message = nil; speakingField = nil
    }
    private var textControls: some View {
        HStack(spacing: 12) {
            if showWizard { CatWizardView().frame(width: 84, height: 78).accessibilityIdentifier("text.processing.cat") }
            if busy && session.translationProgress == nil { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            Spacer(minLength: 0)
            #if os(iOS)
            if editingText {
                Button { editingText = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("Скрыть клавиатуру"))
            }
            #endif
            textPrimaryButton
        }.padding(.horizontal, 20).padding(.vertical, 8)
    }
    private var textPrimaryTitle: String {
        if busy { return L10n.text("Отменить") }
        if !packages.ready { return L10n.text("Скачать модели") }
        #if os(macOS)
        if !session.isReady { return L10n.text("Подготовить перевод") }
        #endif
        return L10n.text("Перевести")
    }
    private var textPrimaryDisabled: Bool {
        if busy { return false }
        if model.languageIssue != nil { return true }
        #if os(iOS)
        return packages.ready && typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #else
        return session.isReady && typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #endif
    }
    private var textPrimaryButton: some View {
            Button(textPrimaryTitle, action: performTextPrimaryAction)
                #if os(iOS)
                .buttonStyle(TextTranslateButtonStyle())
                #else
                .katPrimaryAction().foregroundStyle(.black)
                #endif
                .fontWeight(.semibold)
                .disabled(textPrimaryDisabled)
                .accessibilityIdentifier("text.translate")
    }
    private func performTextPrimaryAction() {
        guard !textPrimaryDisabled else { return }
        editingText = false
        if busy { model.cancel(); return }
        if !packages.ready { showModels = true; return }
        #if os(macOS)
        if !session.isReady { Task { await model.load(resultMode: .text) }; return }
        #endif
        let text = typedText
        Task { await model.translateText(text) }
    }
    private var metrics: some View {
        DisclosureGroup(L10n.text("Измерения"), isExpanded: $showMetrics) {
            measurementValues.padding(.top, 12)
        }.font(.subheadline)
    }
    private var measurementValues: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let load = session.preparationSeconds { DiagnosticsValueRow(L10n.text("Предварительная подготовка"), value: String(format: L10n.text("%.2f с"), locale: L10n.locale, load)) }
            if let sample = session.samples.last {
                if let value = sample.asrLoadSeconds { DiagnosticsValueRow(L10n.text("Загрузка распознавания"), value: String(format: L10n.text("%.2f с"), locale: L10n.locale, value)) }
                if let engine = sample.recognitionModelID { DiagnosticsValueRow(L10n.text("Распознавание речи"), value: recognitionName(engine)) }
                if let value = sample.asrSeconds { DiagnosticsValueRow(L10n.text("Распознавание"), value: String(format: L10n.text("%.2f с"), locale: L10n.locale, value)) }
                if let value = sample.mtLoadSeconds { DiagnosticsValueRow(L10n.text("Загрузка модели перевода"), value: String(format: L10n.text("%.2f с"), locale: L10n.locale, value)) }
                if let value = sample.mtSeconds { DiagnosticsValueRow(L10n.text("Перевод"), value: String(format: L10n.text("%.2f с"), locale: L10n.locale, value)) }
                DiagnosticsValueRow(L10n.text("Создание озвучки"), value: String(format: L10n.text("%.2f с"), locale: L10n.locale, sample.ttsSeconds))
                if let value = sample.playbackScheduledSeconds { DiagnosticsValueRow(L10n.text("До запуска озвучки"), value: String(format: L10n.text("%.2f с"), locale: L10n.locale, value)) }
                Text(L10n.text("Запуск озвучки измеряется программно; физическая задержка динамика отдельно не измерена.")).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
            }
            #if os(macOS)
            Text(L10n.text("Здесь показаны голосовые и текстовые переводы за текущий запуск приложения. Переводы изображений в эти замеры не входят."))
                .font(AppPlatform.panelFootnote).foregroundStyle(.secondary)
            #endif
            Text(L10n.text("Замеров: \(session.samples.count)")).font(AppPlatform.panelCaption)
            Button(L10n.text("Подготовить отчёт")) { model.export() }.disabled(session.samples.isEmpty)
            if let url = model.exportURL { ShareLink(L10n.text("Поделиться отчётом"), item: url) }
            Text(L10n.text("В отчёте только показатели и версии, без голоса и текста.")).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).font(AppPlatform.panelBody)
    }
    private func recognitionName(_ id: String) -> String {
        switch id {
        case RecognitionCatalog.ultraID: "Parakeet Ultra"
        case LanguageSetup.omnilingualID: "Meta Omnilingual"
        case ModelDescriptor.turbo.id: "Whisper"
        default: id
        }
    }
    private var readingText: String {
        switch readingField {
        case .voiceOriginal: return session.voiceFields.sourceText
        case .voiceTranslation: return session.voiceFields.translatedText
        case .textOriginal: return typedText
        case .textTranslation: return session.fields(for: .text).translatedText
        #if os(macOS)
        case .imageTranslation: return imageModel.translatedText
        #endif
        case nil: return ""
        }
    }
    private var voiceTranslationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 2) {
                Text(fields.resolvedTarget.map { TranslationLanguage.shortCode($0.rawValue) } ?? L10n.text("Перевод"))
                    .font(.caption.weight(.semibold)).foregroundStyle(accent)
                    .monospaced().accessibilityLabel(fields.resolvedTarget.map { TranslationLanguage.name($0.rawValue) } ?? L10n.text("Перевод"))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
                ExpandTextButton(enabled: !fields.translatedText.isEmpty, identifier: "voice.translation.expand") { readingField = .voiceTranslation }
                PlaybackSpeedButton(speed: session.playbackSpeed, select: session.setPlaybackSpeed, identifier: "voice.playback.speed")
                if session.isSpeaking && !session.isPlayingOriginalRecording {
                    Button { session.toggleSpeechPause() } label: {
                        Image(systemName: session.isSpeechPaused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(session.isSpeechPaused ? L10n.text("Продолжить озвучку") : L10n.text("Приостановить озвучку"))
                        .accessibilityIdentifier("voice.playback.pauseResume")
                }
                Button {
                    if session.isBusy || model.finishing { model.cancel() }
                    else { Task { await history.applyRecordingSettings(); await session.replay(mode: .voice); await history.refresh() } }
                } label: {
                    Image(systemName: session.isSpeaking ? "speaker.slash.fill" : session.isBusy ? "stop.fill" : "speaker.wave.2")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(session.isSpeaking ? L10n.text("Остановить озвучку") : session.isBusy ? L10n.text("Отменить") : L10n.text("Озвучить перевод"))
                    .accessibilityIdentifier("voice.playback.startStop")
                    .disabled(session.isPlayingOriginalRecording || (!session.isBusy && !model.finishing && !packages.canSpeak(fields.resolvedTarget ?? .english)))
                CopyTextButton(text: fields.translatedText, title: L10n.text("Скопировать перевод"))
                    .accessibilityIdentifier("voice.copy.target")
                #if os(macOS)
                MacShareButton(text: fields.translatedText).disabled(busy)
                    .accessibilityIdentifier("voice.share.text")
                #endif
                #if os(iOS)
                VoiceAudioShareButton(session: session, original: false)
                    .disabled(busy || !session.hasVoiceTranslationSpeech)
                    .accessibilityIdentifier("voice.translation.shareAudio")
                #endif
                Button(action: clearFields) { Image(systemName: AppPlatform.clearSymbol).frame(width: AppPlatform.clearControlSize, height: AppPlatform.clearControlSize) }.katCloseControl()
                    .accessibilityLabel(L10n.text("Очистить перевод"))
            }.katDesktopIconFont()
            if showTechnicalInfo, let timing = fields.timing {
                TranslationTimingView(timing: timing, identifier: "voice.timing")
            }
            if session.isBusy {
                Text(status).font(AppPlatform.panelCaption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("voice.result.status")
            }
            Text(fields.translatedText).font(AppPlatform.voiceTextFont).textSelection(.enabled)
                .frame(minHeight: AppPlatform.voiceResultMinimumHeight, alignment: .topLeading)
                .accessibilityIdentifier("voice.translation.text")
            TextCharacterCount(text: fields.translatedText, identifier: "voice.translation.count")
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }

}

#if os(iOS)
/// Keep the label readable on the black screen even when there is no text yet.
private struct TextTranslateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .frame(minWidth: 112, minHeight: 44)
            .foregroundStyle(isEnabled ? Color.black : KatTheme.accent.opacity(0.65))
            .background(isEnabled ? KatTheme.accent : KatTheme.accent.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
#endif

struct TranslationProgressPanel: View {
    let progress: TranslationProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.text("Перевожу часть \(min(progress.completedParts + 1, progress.totalParts)) из \(progress.totalParts)"))
                Spacer()
                Text("\(Int(progress.fraction * 100)) %").monospacedDigit()
            }.font(.caption)
            ProgressView(value: progress.fraction)
                .accessibilityLabel(L10n.text("Прогресс перевода"))
                .accessibilityValue(L10n.text("\(Int(progress.fraction * 100)) процентов"))
                .accessibilityIdentifier("translation.progress")
            Text(L10n.text("Обработано \(progress.completedCharacters) из \(progress.totalCharacters) символов оригинала"))
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.vertical, 12)
            #if os(macOS)
            .background(.ultraThinMaterial)
            #endif
    }
}
