import SwiftUI
import AVFoundation
import OfflineCore
@MainActor final class AppModel: ObservableObject {
    let downloader = ModelDownloader.shared
    let packages = PackageDownloadCoordinator.shared
    let session: ConversationPipeline
    let history: HistoryModel
    #if os(macOS)
    lazy var camera = CameraModel(packages: packages, history: history, beforePreparing: { [weak self] in await self?.unload() })
    #else
    lazy var camera = CameraModel(packages: packages, history: history)
    #endif
    @Published private(set) var usingCamera = false
    @Published private(set) var isShuttingDown = false
    #if os(macOS)
    private var shutdownTask: Task<Void, Never>?
    lazy var integration = MacIntegration(model: self)
    @Published var externalOperation = false
    @Published private(set) var screenImageRequestID = 0
    @Published private(set) var importingScreenImage = false
    private var screenImageTask: Task<Void, Never>?
    private var pendingScreenImage: (data: Data, languages: LanguageSelection)?
    func requestScreenImage(_ data: Data) {
        guard !isShuttingDown, !externalOperation, !session.isBusy, !recorder.isRecording,
              !recorder.starting, !finishing, !importingAudio, !changingTranslation,
              !camera.recognizing, !camera.opening, !camera.translation.working else { return }
        // Screen captures use the direction selected in the main window.
        pendingScreenImage = (data, languages)
        importingScreenImage = true; externalOperation = true
        screenImageRequestID += 1
    }
    // Wait for the Image tab before opening its model, so tab activation cannot invalidate OCR.
    func activateRequestedScreenImage() {
        guard screenImageTask == nil, let request = pendingScreenImage, !isShuttingDown else { return }
        pendingScreenImage = nil
        screenImageTask = Task {
            defer { importingScreenImage = false; externalOperation = false; screenImageTask = nil }
            languages = request.languages
            await openCamera()
            guard !Task.isCancelled, !isShuttingDown else { return }
            camera.importData(request.data)
        }
    }
    #endif
    private var cameraSwitch = 0
    #if os(iOS)
    private var restoreConversationAfterCamera = false
    private var cameraConversationUnload: Task<Void, Never>?
    #endif
    let recorder = AudioRecorder()
    let voicePreview = VoicePreviewPlayer()
    @Published var languages: LanguageSelection = {
        let defaults = UserDefaults.standard
        let old = defaults.string(forKey: "translationDirection") ?? "ru"
        let source = defaults.string(forKey: "translationSource") ?? (old == "en" ? "en" : "ru")
        let target = defaults.string(forKey: "translationTarget") ?? (source == "ru" ? "en" : "ru")
        let auto = defaults.object(forKey: "automaticLanguage") == nil ? old == "auto" : defaults.bool(forKey: "automaticLanguage")
        let selection = LanguageSelection(sourceID: source, targetID: target, automaticRequested: auto)
        return selection.isAvailable ? selection : LanguageSelection()
    }() {
        didSet {
            UserDefaults.standard.set(languages.sourceID, forKey: "translationSource")
            UserDefaults.standard.set(languages.targetID, forKey: "translationTarget")
            UserDefaults.standard.set(languages.automaticRequested, forKey: "automaticLanguage")
            if oldValue.sourceID != languages.sourceID || oldValue.targetID != languages.targetID { Task { await applyAutoTranslation() } }
        }
    }
    var recognitionPreference: RecognitionPreference {
        RecognitionPreference.restoredSelection(UserDefaults.standard.string(forKey: "recognitionPreference"))
    }
    @Published var showLanguageSetup = false
    @Published var message: String?
    @Published var finishing = false
    @Published private(set) var preparingRecording = false
    @Published private(set) var importingAudio = false
    private var audioFileTask: Task<CapturedAudio, Error>?
    private var audioImportID: UUID?
    @Published private(set) var changingTranslation = false
    @Published var exportURL: URL?
    private var recordingStart = RecordingStartGate()
    private var capturedLanguage: SpeechLanguage? = .russian
    private var capturedTarget: SpeechLanguage = .english
    private var capturedMode = "toggle"
    private var capturedAutomaticSpeech = true
    private var capturedPreview = false
    private var capturedVerification = true
    private var previewFallback: String?
    private var recordingResources: Task<Void, Never>?
    private var peakRecordingFootprint: UInt64 = 0, peakRecordingResident: UInt64 = 0
    private var interactionID = 0
    private var observers: [NSObjectProtocol] = []
    init(session: ConversationPipeline? = nil) {
        TemporarySpeechFiles.prepareForLaunch()
        let store = TranslationHistory(root: ModelDownloader.root.appendingPathComponent("History"))
        history = HistoryModel(store: store)
        self.session = session ?? ConversationPipeline(asr: RoutedASRBackend(), translator: RoutedTranslationBackend(), speech: SherpaSpeechBackend(), player: SpeechPlayer(), archive: store)
        recorder.onLimit = { [weak self] in Task { await self?.finishRecording() } }
        recorder.onBoundary = { [weak self] end in
            guard let self else { return }
            if [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) { self.session.suspendRecordingPreview(reason: "thermal") }
            else { self.session.offerRecordingBoundary(end) }
        }
        recorder.onInterruption = { [weak self] message in self?.cancel(); self?.message = message }
        #if os(iOS)
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == AVAudioSession.interruptionNotification {
                    guard (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue == AVAudioSession.InterruptionType.began.rawValue else { return }
                } else {
                    guard (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                }
                Task { @MainActor in self?.cancel() }
            })
        }
        #endif
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private var automaticLoadAttempted = false
    func prepare() async {
        guard !isShuttingDown else { return }
        #if DOWNLOAD_VALIDATION
        if ["1", "cleanup"].contains(ProcessInfo.processInfo.environment["OT_DOWNLOAD_VALIDATION"] ?? "") {
            automaticLoadAttempted = true
            await DownloadValidationProbe.run { [weak self] in self?.message = $0 }
            return
        }
        #endif
        await history.refresh(); await packages.restore()
        guard !isShuttingDown else { return }
        #if APPLE_SPEECH_PROBE
        if ProcessInfo.processInfo.environment["OT_APPLE_ASR_PROBE"] == "1" {
            automaticLoadAttempted = true
            await AppleSpeechProbe.run(packages: packages) { [weak self] in self?.message = $0 }
            return
        }
        #endif
        #if ASR_COMPARISON_PROBE
        if ProcessInfo.processInfo.environment["OT_ASR_COMPARISON"] == "1" {
            automaticLoadAttempted = true
            do { try await ASRComparisonProbe.run(packages: packages) { [weak self] in self?.message = $0 } }
            catch {
                message = "ASR probe: " + error.localizedDescription
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? message?.write(to: documents.appendingPathComponent("asr-comparison-status.txt"), atomically: true, encoding: .utf8)
            }
            return
        }
        #endif
        #if os(iOS)
        if ProcessInfo.processInfo.environment["OT_RECORDING_PREVIEW_PROBE"] == "1" {
            automaticLoadAttempted = true
            do { try await RecordingPreviewProbe.run(packages: packages) { [weak self] in self?.message = $0 } }
            catch {
                message = "probe-error: " + error.localizedDescription
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? message?.write(to: documents.appendingPathComponent("recording-preview-status.txt"), atomically: true, encoding: .utf8)
            }
            return
        }
        #endif
        if !UserDefaults.standard.bool(forKey: "languageSetupCompleted") {
            if UserDefaults.standard.string(forKey: "selectedTranslationModel") != nil || packages.translationDownloaders.contains(where: { $0.installedURL != nil }) {
                UserDefaults.standard.set(true, forKey: "languageSetupCompleted")
            } else { showLanguageSetup = true }
        }
        await applyAutoTranslation()
        await loadAutomaticallyIfNeeded()
    }
    func loadAutomaticallyIfNeeded() async {
        #if os(macOS)
        guard !externalOperation else { return }
        #endif
        guard !isShuttingDown, !showLanguageSetup, !automaticLoadAttempted, packages.restored, packages.ready, packages.translationTermsAccepted,
              AppPlatform.isActive, !usingCamera, !session.isBusy, !session.isReady,
              !changingTranslation, !importingAudio, !recorder.isRecording, !recorder.starting,
              (UserDefaults.standard.object(forKey: "automaticModelLoad") == nil || UserDefaults.standard.bool(forKey: "automaticModelLoad")) else { return }
        automaticLoadAttempted = true
        let key = "unfinishedAutomaticModelLoad"
        if UserDefaults.standard.string(forKey: key) == packages.selectedTranslation.rawValue {
            message = L10n.text("Предыдущая автозагрузка не завершилась. Подготовьте модель вручную или выберите другую.")
            return
        }
        UserDefaults.standard.set(packages.selectedTranslation.rawValue, forKey: key)
        await load()
        UserDefaults.standard.removeObject(forKey: key)
    }
    func load(resultMode: ConversationMode? = nil) async {
        guard !isShuttingDown else { return }
        automaticLoadAttempted = true
        guard let mt = packages.translationURL else { return }
        let asr = packages.primaryRecognition(for: recognitionPreference)
        message = nil
        await session.prepare(PipelineFiles(asr: asr, translation: mt, voices: packages.selectedVoiceDirectories, voiceModelIDs: packages.selectedVoiceModelIDs, translationModel: packages.selectedTranslation, omnilingual: packages.omnilingualDirectory, ultra: packages.recognition.ultra, recognitionPreference: recognitionPreference, translationResolver: packages.translationResolver), memorySaving: UserDefaults.standard.bool(forKey: "memorySaving"), recognitionLanguage: languages.automaticActive(in: .voice) ? nil : languages.runtimeSource, resultMode: resultMode)
        if UserDefaults.standard.string(forKey: "unfinishedAutomaticModelLoad") == packages.selectedTranslation.rawValue {
            UserDefaults.standard.removeObject(forKey: "unfinishedAutomaticModelLoad")
        }
    }
    func selectTranslation(_ selected: TranslationModel, keepAuto: Bool = false) async {
        guard !isShuttingDown, TranslationModel.selectable.contains(selected) else { return }
        if !keepAuto { packages.setAutoTranslation(false) }
        guard !changingTranslation, !session.isBusy, !finishing, !importingAudio, !recorder.isRecording, !recorder.starting,
              selected != packages.selectedTranslation else { return }
        changingTranslation = true
        defer { changingTranslation = false }
        await closeCamera()
        await unload()
        guard !isShuttingDown else { return }
        packages.selectTranslation(selected)
        message = nil
    }
    /// Auto: switch to the best installed model for the current pair and this device; the
    /// preference stays Auto, only the loaded engine changes.
    func applyAutoTranslation() async {
        guard packages.autoTranslation, packages.restored, let source = languages.runtimeSource, let target = languages.runtimeTarget,
              let resolved = packages.resolvedTranslation(source: source, target: target), resolved != packages.selectedTranslation else { return }
        await selectTranslation(resolved, keepAuto: true)
        automaticLoadAttempted = false
        await loadAutomaticallyIfNeeded()
    }
    func selectVoice(_ item: ModelDownloader, language: SpeechLanguage) async {
        guard !isShuttingDown else { return }
        guard !session.isBusy else { return }
        voicePreview.stop(); packages.selectVoice(item, language: language)
        await refreshVoiceFiles()
    }
    func selectWayuVoice(_ voice: WayuVoice) async {
        guard !isShuttingDown else { return }
        guard !session.isBusy else { return }
        voicePreview.stop(); UserDefaults.standard.set(voice.rawValue, forKey: "wayuVoice")
        packages.objectWillChange.send()
        await refreshVoiceFiles()
    }
    private func refreshVoiceFiles() async {
        guard !isShuttingDown else { return }
        session.updateTranslationResolver(packages.translationResolver)
        await session.updateVoices(packages.selectedVoiceDirectories, modelIDs: packages.selectedVoiceModelIDs)
        await session.updateRecognitionFiles(asr: packages.primaryRecognition(for: recognitionPreference), ultra: packages.recognition.ultra, omnilingual: packages.omnilingualDirectory, preference: recognitionPreference)
    }
    var languageIssue: String? {
        if packages.autoTranslation { return nil } // The actual pair is checked after language detection.
        if languages.automaticActive(in: .text), let target = languages.runtimeTarget {
            return TranslationLanguage.details(target).connected(to: packages.selectedTranslation) ? nil : PipelineError.modelLanguageUnavailable.localizedDescription
        }
        return languages.connected(to: packages.selectedTranslation) ? nil : PipelineError.modelLanguageUnavailable.localizedDescription
    }
    var voiceLanguageIssue: String? {
        if let languageIssue { return languageIssue }
        guard let source = languages.runtimeSource,
              languages.automaticActive(in: .voice) || source.supportsRecognition else { return PipelineError.recognitionUnavailable.localizedDescription }
        let files = PipelineFiles(asr: packages.primaryRecognition(for: recognitionPreference), translation: URL(fileURLWithPath: "/unused"), voices: [:], omnilingual: packages.omnilingualDirectory, ultra: packages.recognition.ultra, recognitionPreference: recognitionPreference)
        do { _ = try files.recognitionURL(for: languages.automaticActive(in: .voice) ? nil : source) }
        catch { return error.localizedDescription }
        return nil
    }
    func beginRecording() async {
        guard !isShuttingDown else { return }
        if let voiceLanguageIssue { message = voiceLanguageIssue; return }
        guard languages.isAvailable, !usingCamera, session.isReady, !session.isBusy, !finishing, !importingAudio, !recorder.starting, !recorder.isRecording,
              let request = recordingStart.begin() else { return }
        preparingRecording = true
        defer { preparingRecording = false }
        await refreshVoiceFiles(); await history.applyRecordingSettings()
        guard !isShuttingDown else { recordingStart.cancel(); return }
        history.stopPlayback()
        capturedTarget = languages.runtimeTarget ?? .english
        capturedAutomaticSpeech = UserDefaults.standard.object(forKey: "automaticSpeechVoice") as? Bool ?? true
        capturedLanguage = languages.automaticActive(in: .voice) ? nil : languages.runtimeSource; capturedMode = UserDefaults.standard.string(forKey: "recordingMode") ?? "toggle"; message = nil
        capturedPreview = UserDefaults.standard.object(forKey: "recordingPreprocessing") as? Bool ?? true
        capturedVerification = UserDefaults.standard.object(forKey: "recordingPreviewVerification") as? Bool ?? true
        previewFallback = capturedPreview ? session.recordingPreviewUnavailable(source: capturedLanguage) : nil
        if capturedPreview, [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) { previewFallback = "thermal" }
        if previewFallback != nil { message = L10n.text("Предварительная обработка недоступна для текущих настроек или температуры. Перевод начнётся после остановки.") }
        interactionID += 1; let id = interactionID
        do {
            let silenceSeconds = UserDefaults.standard.object(forKey: "recordingSilenceSeconds") == nil
                ? SilenceMonitor.defaultTimeout : UserDefaults.standard.double(forKey: "recordingSilenceSeconds")
            RecordingStopTrace.mark("start.silenceSeconds=\(silenceSeconds)")
            let limitMinutes = UserDefaults.standard.object(forKey: "recordingLimitMinutes") as? Double ?? RecordingPolicy.defaultMinutes
            guard id == interactionID, !Task.isCancelled else { throw CancellationError() }
            await session.preloadRecognition(source: capturedLanguage)
            guard id == interactionID else { throw CancellationError() }
            if session.error != nil { throw PipelineError.modelLoad }
            try await recorder.start(silenceSeconds: silenceSeconds, limitMinutes: limitMinutes)
            if !recordingStart.settle(request, succeeded: true) || id != interactionID { recorder.cancel(); return }
            if capturedPreview, previewFallback == nil, let snapshot = recorder.previewSnapshot {
                if !session.beginRecordingPreview(source: capturedLanguage, target: capturedTarget, speakResult: capturedAutomaticSpeech, snapshot: snapshot) { previewFallback = "busy" }
            }
            peakRecordingFootprint = 0; peakRecordingResident = 0
            recordingResources = Task { [weak self] in
                let monitor = ResourceMonitor()
                while !Task.isCancelled {
                    guard let self else { return }
                    monitor.sample()
                    self.peakRecordingFootprint = max(self.peakRecordingFootprint, monitor.footprint ?? 0)
                    self.peakRecordingResident = max(self.peakRecordingResident, monitor.residentMemory ?? 0)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        } catch is CancellationError { recordingStart.settle(request, succeeded: false) }
        catch { recordingStart.settle(request, succeeded: false); if id == interactionID { message = error.localizedDescription } }
    }
    func finishRecording() async {
        guard !isShuttingDown else { return }
        RecordingStopTrace.mark("finish.request")
        recordingStart.cancel()
        guard !finishing else { return }
        guard recorder.isRecording else { if recorder.starting { recorder.cancel() }; return }
        finishing = true; let id = interactionID
        defer {
            if session.isRecordingPreview { session.cancel() }
            finishing = false; recordingResources?.cancel(); recordingResources = nil
        }
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        do {
            let audio = try await recorder.stop()
            RecordingStopTrace.mark("finish.audioReady")
            guard id == interactionID else { return }
            guard audio.durationSeconds >= 0.25 else { message = L10n.text("Запись слишком короткая. Попробуйте ещё раз."); return }
            await refreshVoiceFiles()
            await history.applyRecordingSettings()
            guard id == interactionID, !usingCamera else { return }
            await session.runRecording(audio: audio, speechEnd: recorder.finalSpeechEnd, source: capturedLanguage, target: capturedTarget,
                speakResult: capturedAutomaticSpeech, inputMode: capturedMode, thermal: Self.thermalState, stoppedAt: stoppedAt,
                requestedPreview: capturedPreview, fallbackReason: previewFallback, verifyPreview: capturedVerification)
            if id == interactionID { session.finishRecordingTelemetry(footprint: peakRecordingFootprint, resident: peakRecordingResident, thermal: Self.thermalState) }
            await history.refresh()
        } catch is CancellationError {} catch { if id == interactionID { message = error.localizedDescription } }
    }
    #if os(macOS)
    func importAudioFile(_ url: URL) async {
        guard !isShuttingDown, session.isReady, !usingCamera, !importingAudio, !preparingRecording, !finishing,
              !recorder.isRecording, !recorder.starting, !session.isBusy, !changingTranslation else { return }
        if let voiceLanguageIssue { message = voiceLanguageIssue; return }
        guard languages.isAvailable else { return }
        interactionID += 1; let id = interactionID
        let source = languages.automaticActive(in: .voice) ? nil : languages.runtimeSource
        let target = languages.runtimeTarget
        let defaults = UserDefaults.standard
        let speak = defaults.object(forKey: "automaticSpeechVoice") == nil || defaults.bool(forKey: "automaticSpeechVoice")
        let request = UUID(); audioImportID = request
        importingAudio = true; message = nil
        history.stopPlayback(); voicePreview.stop()
        defer {
            if audioImportID == request { importingAudio = false; audioFileTask = nil; audioImportID = nil }
        }
        do {
            // Sandboxed store builds receive a security-scoped URL from the file importer.
            let task = Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return try AudioFileImport.read(url)
            }
            audioFileTask = task
            let audio = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard id == interactionID, !isShuttingDown, !Task.isCancelled else { return }
            guard id == interactionID, session.isReady, !usingCamera, !Task.isCancelled else { return }
            await refreshVoiceFiles()
            await history.applyRecordingSettings()
            guard id == interactionID, !isShuttingDown, !usingCamera, !Task.isCancelled else { return }
            // From here the pipeline owns busy/cancellation state, including playback.
            // Do not keep the import overlay over the completed text during speech.
            importingAudio = false; audioFileTask = nil
            await session.run(audio: audio, source: source, target: target, speakResult: speak,
                              inputMode: "audio-file", thermal: Self.thermalState)
            await history.refresh()
        } catch is CancellationError {} catch { if id == interactionID { message = error.localizedDescription } }
    }
    #endif
    func translateText(_ text: String) async {
        guard !isShuttingDown else { return }
        if let languageIssue { message = languageIssue; return }
        guard !usingCamera, languages.runtimeSource != nil, !recorder.isRecording, !recorder.starting, !finishing, !importingAudio else { return }
        guard !session.isBusy else { return }
        let source = languages.automaticActive(in: .text) ? nil : languages.runtimeSource
        let target = languages.runtimeTarget, speak = UserDefaults.standard.bool(forKey: "automaticSpeechText")
        interactionID += 1; let id = interactionID
        history.stopPlayback(); message = nil
        #if os(iOS)
        // The mobile Translate action also prepares models on its first use.
        if !session.isReady { await load() }
        guard id == interactionID, !isShuttingDown, !usingCamera, session.isReady, !Task.isCancelled else { return }
        #endif
        await refreshVoiceFiles()
        await history.applyRecordingSettings()
        guard id == interactionID, !usingCamera else { return }
        await session.run(audio: nil, text: text, source: source, target: target, speakResult: speak, inputMode: "text", thermal: Self.thermalState)
        await history.refresh()
    }
    func readText(_ text: String, language: SpeechLanguage, isTranslation: Bool) async {
        guard !isShuttingDown else { return }
        guard !usingCamera, !session.isBusy, !recorder.isRecording, !recorder.starting, !finishing, !importingAudio else { return }
        interactionID += 1; let id = interactionID
        history.stopPlayback(); voicePreview.stop(); message = nil
        if !session.isReady { await load() }
        await refreshVoiceFiles()
        guard id == interactionID, !usingCamera, session.isReady, !Task.isCancelled else { return }
        await history.applyRecordingSettings()
        guard id == interactionID, !usingCamera, !Task.isCancelled else { return }
        await session.readAloud(text, language: language, mode: .text, archiveOriginal: !isTranslation)
        await history.refresh()
    }
    func openCamera() async {
        guard !isShuttingDown else { return }
        #if os(iOS)
        if !usingCamera { restoreConversationAfterCamera = restoreConversationAfterCamera || session.isReady }
        #endif
        cameraSwitch += 1; let id = cameraSwitch; usingCamera = true
        #if os(iOS)
        // Camera has its own translator. Drain Voice before allocating it, but
        // remember readiness so returning to Voice/Text needs no preparation tap.
        automaticLoadAttempted = true
        cancel()
        let unloading = Task { await session.unload() }
        cameraConversationUnload = unloading
        await unloading.value
        #endif
        await packages.restore()
        guard !isShuttingDown, id == cameraSwitch, !Task.isCancelled else { return }
        guard let source = languages.runtimeSource else { return }
        let automatic = languages.automaticActive(in: .camera), target = languages.runtimeTarget ?? .russian
        let changed = camera.automaticSource != automatic || camera.target != target || (!automatic && camera.source != source)
        camera.automaticSource = automatic
        if !automatic { camera.source = source }
        camera.target = target
        await camera.open(modelURL: packages.translationURL)
        if changed && camera.hasResult {
            #if os(macOS)
            if !importingScreenImage { camera.recognize() }
            #else
            await camera.changedOptions()
            #endif
        }
    }
    func closeCamera(resumingConversation: Bool = false) async {
        #if os(iOS)
        // Backgrounding, changing/removing a model and memory warnings close
        // without resuming. Explicit unload must keep its usual meaning too.
        if !resumingConversation { restoreConversationAfterCamera = false }
        #endif
        if usingCamera {
            cameraSwitch += 1; let id = cameraSwitch
            await camera.close()
            #if os(iOS)
            // The user can leave before openCamera finishes draining Voice.
            await cameraConversationUnload?.value
            #endif
            guard id == cameraSwitch else { return }
            usingCamera = false
            #if os(iOS)
            cameraConversationUnload = nil
            #endif
        }
        #if os(iOS)
        guard resumingConversation, restoreConversationAfterCamera, !usingCamera,
              !isShuttingDown, !Task.isCancelled, AppPlatform.isActive,
              !changingTranslation, !session.isBusy else { return }
        let id = cameraSwitch
        await load()
        if id == cameraSwitch { restoreConversationAfterCamera = false }
        #endif
    }
    func cancel() {
        #if os(macOS)
        integration.cancel()
        #endif
        audioFileTask?.cancel(); recordingResources?.cancel(); recordingResources = nil; voicePreview.stop(); history.stopPlayback(); interactionID += 1; recordingStart.cancel(); recorder.cancel(); session.cancel() }
    #if os(macOS)
    /// AppKit defers process exit until every native inference queue is drained.
    /// A terminal state: pending UI/startup tasks must never start another load.
    func shutdown() async {
        if let shutdownTask { await shutdownTask.value; return }
        isShuttingDown = true
        integration.stop(); screenImageTask?.cancel()
        automaticLoadAttempted = true
        cameraSwitch += 1
        cancel()
        let task = Task {
            await camera.close()
            usingCamera = false
            await session.unload()
            await packages.pauseAll()
            clearTemporaryAudio()
        }
        shutdownTask = task
        await task.value
    }
    #endif
    func clearTemporaryAudio() {
        session.clearTemporarySpeech()
        TemporarySpeechFiles.removeExports()
    }
    func background() { cancel() }
    func unload() async {
        #if os(iOS)
        restoreConversationAfterCamera = false
        #endif
        automaticLoadAttempted = true; cancel(); await session.unload()
    }
    func removeModel(_ item: ModelDownloader) async {
        #if os(macOS)
        await closeCamera()
        #endif
        await unload(); await packages.remove(item)
    }
    func memoryWarning() async {
        if recorder.isRecording, session.isRecordingPreview {
            session.suspendRecordingPreview(reason: "memory-warning")
            message = L10n.text("Предварительная обработка приостановлена. Запись продолжается.")
            return
        }
        if !usingCamera, await session.relieveMemoryPressure() { return }
        message = L10n.text("Модели выгружены для освобождения памяти. Включите экономию памяти в настройках и подготовьте перевод снова.")
        await closeCamera(); await unload()
    }
    func export() {
        do {
            var system = utsname(); uname(&system)
            let capacity = MemoryLayout.size(ofValue: system.machine)
            let machine = withUnsafePointer(to: &system.machine) { $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) } }
            let data = try PipelineBenchmark.export(session.samples, device: machine, osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("translation-benchmarks.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection]); exportURL = url
        } catch { message = error.localizedDescription }
    }
    static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
