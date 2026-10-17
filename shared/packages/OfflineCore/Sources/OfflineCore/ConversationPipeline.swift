import Foundation
import Combine
@MainActor public protocol SpeechPlayback: AnyObject {
    func play(_ pcm: SpeechPCM) async throws
    func play(file: URL) async throws
    func stop()
    func pause()
    func resume()
    func setRate(_ rate: Float)
}
public struct TranslationInstallation: Sendable {
    public let model: TranslationModel
    public let url: URL
    public init(model: TranslationModel, url: URL) { self.model = model; self.url = url }
}
public typealias TranslationResolver = @MainActor @Sendable (SpeechLanguage, SpeechLanguage) throws -> TranslationInstallation
public struct PipelineFiles: Sendable {
    public let translationResolver: TranslationResolver?
    public func replacingTranslation(_ value: TranslationInstallation) -> PipelineFiles {
        PipelineFiles(asr: asr, translation: value.url, voices: voices, voiceModelIDs: voiceModelIDs,
            translationModel: value.model, omnilingual: omnilingual, ultra: ultra,
            recognitionPreference: recognitionPreference, translationResolver: translationResolver)
    }
    public let asr: URL?
    public let translation: URL
    public let omnilingual: URL?
    public let ultra: URL?
    public let recognitionPreference: RecognitionPreference
    public func recognitionURL(for language: SpeechLanguage?) throws -> URL {
        switch recognitionPreference {
        case .automatic: break
        case .whisper:
            guard language == nil || language?.whisperCode != nil else { throw PipelineError.recognitionUnavailable }
            guard let asr, asr.lastPathComponent == ModelDescriptor.turbo.id + ".bin" else { throw RecognitionError.downloadRequired }
            return asr
        case .ultra:
            guard RecognitionCatalog.prefersUltra(language) else { throw PipelineError.recognitionUnavailable }
            guard let ultra else { throw RecognitionError.downloadRequired }
            return ultra

        }
        guard let language, language.whisperCode == nil else {
            guard let asr else { throw RecognitionError.downloadRequired }
            return asr
        }
        guard RecognitionCatalog.omnilingualCodes[language.rawValue] != nil else { throw PipelineError.recognitionUnavailable }
        guard let omnilingual else { throw RecognitionError.downloadRequired }
        return omnilingual
    }
    public let translationModel: TranslationModel
    public let voices: [SpeechLanguage: URL]
    public let voiceModelIDs: [SpeechLanguage: String]
    public var russianVoice: URL? { voices[.russian] }
    public var englishVoice: URL? { voices[.english] }
    public func voice(_ language: SpeechLanguage) -> URL? { voices[language] }
    public init(asr: URL?, translation: URL, voices: [SpeechLanguage: URL], voiceModelIDs: [SpeechLanguage: String] = [:], translationModel: TranslationModel = .index9B, omnilingual: URL? = nil, ultra: URL? = nil, recognitionPreference: RecognitionPreference = .automatic, translationResolver: TranslationResolver? = nil) {
        self.translationResolver = translationResolver
        self.recognitionPreference = recognitionPreference
        self.ultra = ultra; self.omnilingual = omnilingual; self.translationModel = translationModel; self.asr = asr; self.translation = translation; self.voices = voices; self.voiceModelIDs = voiceModelIDs
    }
    public init(asr: URL?, translation: URL, russianVoice: URL?, englishVoice: URL?) {
        self.init(asr: asr, translation: translation, voices: [.russian: russianVoice, .english: englishVoice].compactMapValues { $0 })
    }
}
public enum ConversationMode: Sendable, Hashable { case voice, text, quick }
/// Completed engine work for this result, excluding model loading, recording and speech playback.
public struct TranslationTiming: Sendable, Equatable {
    public let recognitionSeconds: Double?
    public let translationSeconds: Double
    public var totalSeconds: Double { (recognitionSeconds ?? 0) + translationSeconds }
}
public struct ConversationFields: Sendable {
    public var sourceText = ""
    public var translatedText = ""
    public var resolvedSource: SpeechLanguage?
    public var resolvedTarget: SpeechLanguage?
    public var lastHistoryID: UUID?
    public var speechNotice: String?
    public var archiveWarning: String?
    public var error: String?
    public var timing: TranslationTiming?
    public init() {}
}
@MainActor public final class ConversationPipeline: ObservableObject {
    @Published public private(set) var voiceFields = ConversationFields()
    @Published public private(set) var textFields = ConversationFields()
    @Published public private(set) var quickFields = ConversationFields()
    @Published public private(set) var activeMode: ConversationMode = .voice
    public func fields(for mode: ConversationMode) -> ConversationFields {
        switch mode { case .voice: voiceFields; case .text: textFields; case .quick: quickFields }
    }
    private var currentFields: ConversationFields {
        get { fields(for: activeMode) }
        set {
            switch activeMode { case .voice: voiceFields = newValue; case .text: textFields = newValue; case .quick: quickFields = newValue }
        }
    }
    public private(set) var sourceText: String { get { currentFields.sourceText } set { currentFields.sourceText = newValue } }
    public private(set) var translatedText: String { get { currentFields.translatedText } set { currentFields.translatedText = newValue } }
    public private(set) var resolvedSource: SpeechLanguage? { get { currentFields.resolvedSource } set { currentFields.resolvedSource = newValue } }
    public private(set) var resolvedTarget: SpeechLanguage? { get { currentFields.resolvedTarget } set { currentFields.resolvedTarget = newValue } }
    public private(set) var speechNotice: String? { get { currentFields.speechNotice } set { currentFields.speechNotice = newValue } }
    public private(set) var archiveWarning: String? { get { currentFields.archiveWarning } set { currentFields.archiveWarning = newValue } }
    public private(set) var lastHistoryID: UUID? { get { currentFields.lastHistoryID } set { currentFields.lastHistoryID = newValue } }
    public private(set) var error: String? { get { currentFields.error } set { currentFields.error = newValue } }
    @Published public private(set) var stage = ""
    @Published public private(set) var translationProgress: TranslationProgress?
    @Published public private(set) var isBusy = false
    @Published public private(set) var isSpeaking = false
    @Published public private(set) var isWaitingForSpeech = false
    @Published public private(set) var isSpeechPaused = false
    @Published public private(set) var hasOriginalRecording = false
    @Published public private(set) var isPlayingOriginalRecording = false
    @Published public private(set) var playbackSpeed = PlaybackSpeed.normal
    public func toggleSpeechPause() {
        guard isSpeaking else { return }
        isSpeechPaused.toggle()
        if isSpeechPaused { player.pause() } else { player.resume() }
    }
    public func setPlaybackSpeed(_ speed: PlaybackSpeed) {
        playbackSpeed = speed
        player.setRate(Float(speed.rawValue))
    }
    @Published public private(set) var isReady = false
    @Published public private(set) var samples: [PipelineBenchmark] = []
    @Published public private(set) var preparationSeconds: Double?
    private let asr: any ASRBackend
    private let translator: any TranslationBackend
    private let speech: any SpeechSynthesisBackend
    private let player: any SpeechPlayback
    private let archive: (any TranslationArchive)?
    private struct ArchivedSpeech: Equatable {
        let historyID: UUID
        let text: String
        let language: SpeechLanguage
        let voice: URL?
        let voiceModelID: String?
    }
    private let textSpeechShareCache = TextSpeechShareCache()
    private let voiceSpeechShareCache = TextSpeechShareCache()
    private let voiceRecording = VoiceRecordingCache()
    private var archivedSpeech: [ConversationMode: ArchivedSpeech] = [:]
    private var archivedOriginalSpeech: [ConversationMode: ArchivedSpeech] = [:]
    private func speechIdentity(text: String, language: SpeechLanguage, files: PipelineFiles) -> ArchivedSpeech? {
        guard let historyID = lastHistoryID, resolvedTarget == language,
              translatedText.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return nil }
        return ArchivedSpeech(historyID: historyID, text: text, language: language,
                              voice: files.voice(language), voiceModelID: files.voiceModelIDs[language])
    }
    private var recordingPreview: RecordingPreviewCoordinator?
    @Published public private(set) var isRecordingPreview = false
    private var nextSpeech: Task<PreparedSpeech?, Error>?
    private var files: PipelineFiles?
    private var memorySaving = false
    private var recognitionReleasePending = false
    private var asrLoaded = false, mtLoaded = false
    private var loadedASRURL: URL?
    private var voiceLoaded: SpeechLanguage?
    private var generation = 0
    private var active: Task<Void, Never>?
    private var unloading: Task<Void, Never>?
    public init(asr: any ASRBackend, translator: any TranslationBackend, speech: any SpeechSynthesisBackend, player: any SpeechPlayback, archive: (any TranslationArchive)? = nil) {
        self.asr = asr; self.translator = translator; self.speech = speech; self.player = player; self.archive = archive
    }
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private func check(_ id: Int) throws { try Task.checkCancellation(); if id != generation { throw CancellationError() } }
    public func prepare(_ files: PipelineFiles, memorySaving: Bool, recognitionLanguage: SpeechLanguage? = nil, resultMode: ConversationMode? = nil) async {
        guard !isBusy, unloading == nil else { return }
        if let resultMode { activeMode = resultMode }
        generation += 1; let id = generation; isBusy = true; isReady = false; error = nil
        let previousFiles = self.files
        self.files = files; self.memorySaving = memorySaving
        let job = Task {
            let start = now
            defer { isBusy = false; stage = ""; active = nil }
            do {
                if mtLoaded, memorySaving || previousFiles?.translation != files.translation || previousFiles?.translationModel != files.translationModel { await translator.unload(); mtLoaded = false }
                try check(id)
                let initialASR = try? files.recognitionURL(for: recognitionLanguage)
                if asrLoaded, loadedASRURL != initialASR { await asr.unload(); asrLoaded = false; loadedASRURL = nil }
                if let initialASR, !files.translationModel.defersRecognitionLoading || (!memorySaving && initialASR.lastPathComponent == RecognitionCatalog.ultraID) {
                    if !asrLoaded { stage = L10n.text("Загружаю распознавание…"); try await asr.load(modelURL: initialASR); asrLoaded = true; loadedASRURL = initialASR }
                }
                try check(id)
                if !memorySaving, !mtLoaded { stage = L10n.text("Загружаю перевод…"); try await translator.load(modelURL: files.translation, model: files.translationModel); mtLoaded = true }
                await releaseRecognitionIfRequested()
                try check(id); preparationSeconds = now - start; isReady = true
            } catch is CancellationError {} catch { if id == generation { self.error = error.localizedDescription } }
        }
        active = job; await job.value
    }
    public func updateTranslationResolver(_ resolver: TranslationResolver?) {
        guard !isBusy, let old = files else { return }
        files = PipelineFiles(asr: old.asr, translation: old.translation, voices: old.voices,
            voiceModelIDs: old.voiceModelIDs, translationModel: old.translationModel, omnilingual: old.omnilingual,
            ultra: old.ultra, recognitionPreference: old.recognitionPreference, translationResolver: resolver)
    }
    private func resolveTranslation(_ current: PipelineFiles, source: SpeechLanguage, target: SpeechLanguage, generation id: Int) async throws -> PipelineFiles {
        guard source != target, let resolve = current.translationResolver else { return current }
        let installation = try resolve(source, target)
        guard installation.model != current.translationModel || installation.url != current.translation else { return current }
        if mtLoaded { await translator.unload(); mtLoaded = false }
        try check(id)
        let updated = current.replacingTranslation(installation)
        files = updated
        return updated
    }
    public func updateVoices(russian: URL?, english: URL?) async {
        await updateVoices([.russian: russian, .english: english].compactMapValues { $0 })
    }
    public func updateVoices(_ voices: [SpeechLanguage: URL], modelIDs: [SpeechLanguage: String] = [:]) async {
        guard !isBusy, unloading == nil, let old = files, (old.voices != voices || old.voiceModelIDs != modelIDs) else { return }
        generation += 1; let id = generation
        isBusy = true; stage = L10n.text("Меняю голос…")
        let job = Task {
            defer { isBusy = false; stage = ""; active = nil }
            await speech.unload(); voiceLoaded = nil
            guard id == generation, !Task.isCancelled else { return }
            files = PipelineFiles(asr: old.asr, translation: old.translation, voices: voices, voiceModelIDs: modelIDs, translationModel: old.translationModel, omnilingual: old.omnilingual, ultra: old.ultra, recognitionPreference: old.recognitionPreference, translationResolver: old.translationResolver)
        }
        active = job; await job.value
    }
    public func updateRecognitionPackage(_ url: URL?) async {
        guard let old = files else { return }
        await updateRecognitionFiles(asr: old.asr, ultra: old.ultra, omnilingual: url, preference: old.recognitionPreference)
    }
    public func updateRecognitionFiles(asr primary: URL?, ultra: URL?, omnilingual: URL?, preference: RecognitionPreference? = nil) async {
        guard !isBusy, unloading == nil, let old = files,
              old.asr != primary || old.ultra != ultra || old.omnilingual != omnilingual || (preference != nil && preference != old.recognitionPreference) else { return }
        generation += 1; let id = generation
        isBusy = true
        let job = Task {
            defer { isBusy = false; active = nil }
            if asrLoaded { await asr.unload(); asrLoaded = false; loadedASRURL = nil }
            guard id == generation, !Task.isCancelled else { return }
            files = PipelineFiles(asr: primary, translation: old.translation, voices: old.voices,
                voiceModelIDs: old.voiceModelIDs, translationModel: old.translationModel, omnilingual: omnilingual, ultra: ultra, recognitionPreference: preference ?? old.recognitionPreference, translationResolver: old.translationResolver)
        }
        active = job; await job.value
    }
    /// Warm the selected recognizer before microphone capture, not after the user stops speaking.
    public func preloadRecognition(source: SpeechLanguage?) async {
        guard isReady, !isBusy, unloading == nil, let files else { return }
        generation += 1; let id = generation
        isBusy = true; error = nil
        let job = Task {
            defer { isBusy = false; stage = ""; active = nil }
            do {
                let url = try files.recognitionURL(for: source)
                if asrLoaded, loadedASRURL != url { await asr.unload(); asrLoaded = false; loadedASRURL = nil }
                try check(id)
                if !asrLoaded {
                    // Respect the existing low-memory policy when warming before capture.
                    if memorySaving, mtLoaded { await translator.unload(); mtLoaded = false }
                    if memorySaving, voiceLoaded != nil { await speech.unload(); voiceLoaded = nil }
                    stage = L10n.text("Загружаю распознавание…")
                    try await asr.load(modelURL: url); asrLoaded = true; loadedASRURL = url
                }
                try check(id)
            } catch is CancellationError {} catch { if id == generation { self.error = error.localizedDescription } }
        }
        active = job; await job.value
    }

    public func run(audio: CapturedAudio?, text: String = "", source requestedSource: SpeechLanguage?, target requestedTarget: SpeechLanguage? = nil, speakResult: Bool = true, inputMode: String, thermal: String, preview: RecordingPreviewResult? = nil, stoppedAt: Double? = nil, recordedSeconds: Double? = nil, processingMode: String = "after-stop", fallbackReason: String? = nil, verifyPreview: Bool = false, resultMode: ConversationMode? = nil, originalRecording: CapturedAudio? = nil) async {
        guard isReady, !isBusy, unloading == nil, let files else { return }
        generation += 1; let id = generation
        activeMode = resultMode ?? (audio == nil ? .text : .voice)
        if activeMode == .voice { voiceRecording.clear(); voiceSpeechShareCache.clear(); hasOriginalRecording = false }
        currentFields.timing = nil
        isBusy = true; error = nil; resolvedSource = nil; resolvedTarget = nil; speechNotice = nil; sourceText = ""; translatedText = ""; lastHistoryID = nil; archiveWarning = nil; player.stop()
        let job = Task {
            var files = files
            var source = verifyPreview ? requestedSource : (preview?.source ?? requestedSource)
            var metric = PipelineBenchmark(source: requestedSource, inputKind: audio == nil ? "text" : "speech", inputMode: inputMode,
                audioSeconds: recordedSeconds ?? audio?.durationSeconds, thermalState: thermal, memorySaving: memorySaving)
            metric.translationModelID = files.translationModel.rawValue
            metric.processingMode = processingMode; metric.fallbackReason = preview?.fallbackReason ?? fallbackReason
            metric.preprocessingSeconds = preview?.processingSeconds
            metric.previewBlocks = preview?.blocks
            metric.asrSeconds = preview?.asrSeconds; metric.mtSeconds = preview?.mtSeconds
            let start = stoppedAt ?? now
            var earlyPlayback: Task<Void, Error>?
            var earlySpeech: RecordingPreviewSpeech?
            var streamedStart: StreamedSpeechStart?
            var earlyAudioHistoryID: UUID?
            var newText = ""
            var validatedSpeech = verifyPreview ? nil : preview?.firstSpeech
            sourceText = verifyPreview ? "" : (preview?.sourceText ?? ""); translatedText = verifyPreview ? "" : (preview?.translatedText ?? "")
            defer { earlyPlayback?.cancel(); streamedStart?.cancel(); isSpeaking = false; isSpeechPaused = false; translationProgress = nil; player.stop(); metric.totalSeconds = now - start; samples.append(metric); isBusy = false; stage = ""; active = nil }
            do {
                if activeMode == .voice, let recording = originalRecording {
                    do {
                        try await voiceRecording.replace(with: recording)
                        try check(id); hasOriginalRecording = true
                    } catch is CancellationError { throw CancellationError() }
                    catch { archiveWarning = L10n.text("Не удалось сохранить запись оригинала: ") + error.localizedDescription }
                }
                if !verifyPreview, speakResult, let prepared = preview?.firstSpeech,
                   let target = preview?.target, voiceLoaded == target,
                   translatedText.hasPrefix(prepared.text) {
                    earlySpeech = prepared; isSpeaking = true; isSpeechPaused = false
                    player.setRate(Float(playbackSpeed.rawValue))
                    metric.playbackScheduledSeconds = now - start
                    metric.ttsSeconds += prepared.seconds
                    metric.spokenSeconds += Double(prepared.pcm.samples.count) / Double(prepared.pcm.sampleRate)
                    metric.ttsFragments += 1
                    earlyPlayback = Task { try await player.play(prepared.pcm) }
                }
                if memorySaving, voiceLoaded != nil { await speech.unload(); voiceLoaded = nil }
                try check(id)
                if let audio, !audio.samples.isEmpty {
                    if memorySaving, mtLoaded { await translator.unload(); mtLoaded = false }
                    try check(id)
                    let recognitionURL = try files.recognitionURL(for: source)
                    if asrLoaded && loadedASRURL != recognitionURL { await asr.unload(); asrLoaded = false; loadedASRURL = nil }
                    try check(id)
                    if !asrLoaded { let t = now; stage = L10n.text("Загружаю распознавание…"); try await asr.load(modelURL: recognitionURL); asrLoaded = true; loadedASRURL = recognitionURL; metric.asrLoadSeconds = now - t }
                    try check(id); stage = requestedSource == nil ? L10n.text("Определяю язык и распознаю…") : L10n.text("Распознаю речь…")
                    if verifyPreview { stage = L10n.text("Проверяю распознанный текст…") }
                    let verificationStart = now
                    let result = try await asr.transcribe(audio, language: source)
                    metric.recognitionModelID = result.engineID
                    try check(id)
                    source = source ?? result.language
                    newText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    sourceText = verifyPreview ? newText : [sourceText, newText].filter { !$0.isEmpty }.joined(separator: " ")
                    if verifyPreview { metric.verificationSeconds = now - verificationStart }
                    metric.asrSeconds = (metric.asrSeconds ?? 0) + result.processingSeconds
                } else if audio == nil {
                    newText = text.trimmingCharacters(in: .whitespacesAndNewlines); sourceText = newText
                    if requestedSource == nil { source = TextLanguageDetection.detect(sourceText) }
                }
                guard let source else { throw PipelineError.textNeedsLanguage }
                resolvedSource = source; metric.source = source
                guard requestedTarget != nil || [SpeechLanguage.russian, .english].contains(source) else { throw PipelineError.textNeedsLanguage }
                let target = requestedTarget ?? source.opposite
                resolvedTarget = target; metric.target = target
                files = try await resolveTranslation(files, source: source, target: target, generation: id)
                metric.translationModelID = files.translationModel.rawValue
                guard source == target || files.translationModel.supports(source: source, target: target) else { throw PipelineError.modelLanguageUnavailable }
                metric.voiceModelID = files.voiceModelIDs[target] ?? files.voice(target)?.lastPathComponent
                guard !sourceText.isEmpty else { throw PipelineError.noSpeech }
                if activeMode == .voice, let recording = voiceRecording.url, let archive {
                    do { _ = try await archive.saveOriginalRecording(recording, text: sourceText, language: source) }
                    catch { archiveWarning = L10n.text("Не удалось сохранить запись оригинала: ") + error.localizedDescription }
                    try check(id)
                }
                await releaseRecognitionIfRequested()
                if memorySaving, asrLoaded { await asr.unload(); asrLoaded = false }
                try check(id)
                let reconciliation = verifyPreview ? RecordingReconciliation(finalText: sourceText,
                    blocks: preview?.source == source && preview?.target == target ? (preview?.translations ?? []) : []) : nil
                if let reconciliation {
                    metric.reusedPreviewBlocks = reconciliation.reusedBlocks
                    metric.retranslatedParts = reconciliation.parts.filter { $0.translation == nil }.count
                    if let cached = preview?.firstSpeech, !cached.text.isEmpty, reconciliation.confirmedPrefix.hasPrefix(cached.text) {
                        validatedSpeech = cached
                    }
                }
                let parts = reconciliation?.parts ?? (newText.isEmpty ? [] : [RecordingReconciliation.Part(source: newText, translation: nil)])
                for part in parts {
                    try check(id)
                    if source == target {
                        translatedText = [translatedText, part.source].filter { !$0.isEmpty }.joined(separator: " ")
                        continue
                    }
                    if let cached = part.translation {
                        translatedText = [translatedText, cached].filter { !$0.isEmpty }.joined(separator: " ")
                        continue
                    }
                if !mtLoaded { let t = now; stage = L10n.text("Загружаю перевод…"); try await translator.load(modelURL: files.translation, model: files.translationModel); mtLoaded = true; metric.mtLoadSeconds = now - t }
                try check(id); stage = L10n.text("Перевожу…")
                translationProgress = part.source.count >= 1000 ? TranslationWork(pieces: [part.source]).progress : nil
                // The first finished sentence is spoken while the rest is generated; the text itself is unchanged.
                if streamedStart == nil, speakResult, !memorySaving, earlySpeech == nil, translatedText.isEmpty, files.voice(target) != nil {
                    streamedStart = StreamedSpeechStart()
                }
                let streaming = translatedText.isEmpty ? streamedStart : nil
                let result = try await translator.translate(text: part.source, source: source, target: target, progress: { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id, let current = self.translationProgress,
                              update.totalCharacters == current.totalCharacters,
                              update.revision >= current.revision,
                              update.completedCharacters >= current.completedCharacters else { return }
                        self.translationProgress = update
                    }
                }, partial: { [weak self] text in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id, let streaming else { return }
                        streaming.offer(text, prepare: { sentence in
                            guard let voice = files.voice(target) else { return nil }
                            try self.check(id)
                            if self.voiceLoaded != target { self.voiceLoaded = nil; try await self.speech.load(directory: voice, language: target); self.voiceLoaded = target }
                            try self.check(id)
                            guard let part = try await SpeechPreparation(text: sentence, speech: self.speech).next() else { return nil }
                            try self.check(id)
                            return RecordingPreviewSpeech(text: part.text, pcm: part.pcm, seconds: part.synthesisSeconds)
                        }, play: { prepared in
                            self.isSpeaking = true; self.isSpeechPaused = false
                            self.player.setRate(Float(self.playbackSpeed.rawValue))
                            return Task { try await self.player.play(prepared.pcm) }
                        })
                    }
                })
                translationProgress = nil
                try check(id)
                guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PipelineError.inference }
                translatedText = [translatedText, result.text].filter { !$0.isEmpty }.joined(separator: " ")
                metric.mtSeconds = (metric.mtSeconds ?? 0) + result.processingSeconds; metric.firstTokenSeconds = result.firstTokenSeconds; metric.mtFragments += result.fragments
                }
                guard !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PipelineError.inference }
                // Freeze timings with the completed result, before history I/O or automatic speech.
                currentFields.timing = TranslationTiming(recognitionSeconds: metric.asrSeconds, translationSeconds: metric.mtSeconds ?? 0)
                if let archive {
                    do {
                        let entry = try await archive.save(original: sourceText, translation: translatedText, source: source, target: target)
                        try check(id); lastHistoryID = entry
                    } catch is CancellationError { throw CancellationError() }
                    catch { if id == generation { archiveWarning = L10n.text("Не удалось сохранить историю: ") + error.localizedDescription } }
                }
                try check(id)
                await releaseRecognitionIfRequested()
                if memorySaving { await translator.unload(); mtLoaded = false }
                try check(id)
                if files.voice(target) == nil { speechNotice = target.hasVoice ? L10n.text("Скачайте голос в настройках, чтобы озвучить перевод.") : L10n.text("Для этого языка пока доступен перевод без озвучки.") }
                if let streamedStart, streamedStart.started {
                    await streamedStart.finish(); try check(id)
                    if let prepared = streamedStart.speech {
                        if translatedText.hasPrefix(prepared.text) {
                            earlySpeech = prepared
                            metric.playbackScheduledSeconds = streamedStart.startedAt.map { $0 - start }
                            metric.ttsSeconds += prepared.seconds; metric.ttsFragments += 1
                            metric.spokenSeconds += Double(prepared.pcm.samples.count) / Double(prepared.pcm.sampleRate)
                        } else { player.stop() } // A retried translation changed the start: speak it in full.
                    }
                }
                if let earlyPlayback { try await earlyPlayback.value; try check(id) }
                if let earlySpeech, let archive, let entry = lastHistoryID {
                    earlyAudioHistoryID = entry
                    do { try await archive.appendAudio(earlySpeech.pcm, to: entry) }
                    catch { await archive.abortAudio(entry); lastHistoryID = nil; archiveWarning = L10n.text("Озвучка не сохранена: ") + error.localizedDescription }
                }
                if speakResult, files.voice(target) != nil {
                    let remaining = earlySpeech.map { String(translatedText.dropFirst($0.text.count)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? translatedText
                    try await speak(remaining, target: target, id: id, files: files, metric: &metric, start: start, historyID: lastHistoryID,
                        cached: earlySpeech == nil ? validatedSpeech : nil, continuingPlayback: earlySpeech != nil, completedPrefix: earlySpeech?.pcm)
                }
                metric.status = "completed"
            } catch is CancellationError {
                if let archive, let entry = earlyAudioHistoryID { await archive.abortAudio(entry) }
                metric.status = "cancelled"
            } catch {
                if let archive, let entry = earlyAudioHistoryID { await archive.abortAudio(entry) }
                metric.status = id == generation ? "failed" : "cancelled"
                if id == generation { self.error = error.localizedDescription }
            }
            await releaseRecognitionIfRequested()
        }
        active = job; await job.value
    }
    private func speak(_ text: String, target: SpeechLanguage, id: Int, files: PipelineFiles, metric: inout PipelineBenchmark, start: Double, historyID: UUID? = nil, cached: RecordingPreviewSpeech? = nil, continuingPlayback: Bool = false, completedPrefix: SpeechPCM? = nil, archiveOriginal: Bool = false) async throws {
        guard let voice = files.voice(target) else { throw PipelineError.voiceUnavailable }
        if !continuingPlayback { isSpeechPaused = false }
        player.setRate(Float(playbackSpeed.rawValue))
        isSpeaking = true; isWaitingForSpeech = !continuingPlayback
        defer { isSpeaking = false; isSpeechPaused = false; isWaitingForSpeech = false }
        if voiceLoaded != target {
            voiceLoaded = nil; stage = L10n.text("Загружаю голос…"); let t = now
            try await speech.load(directory: voice, language: target)
            voiceLoaded = target; metric.ttsLoadSeconds = now - t
        }
        try check(id)
        let validCache = cached.flatMap { text.hasPrefix($0.text) ? $0 : nil }
        let remaining = validCache.map { String(text.dropFirst($0.text.count)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? text
        let producer = try SpeechPreparation(text: remaining, speech: speech)
        var savingID = historyID
        let shareCache: TextSpeechShareCache? = activeMode == .text ? textSpeechShareCache : activeMode == .voice ? voiceSpeechShareCache : nil
        do {
            try shareCache?.begin(text: continuingPlayback ? translatedText : text, language: target, original: archiveOriginal)
            if let completedPrefix { try shareCache?.append(completedPrefix) }
        } catch {
            shareCache?.abort(); archiveWarning = L10n.text("Озвучка не сохранена: ") + error.localizedDescription
        }
        nextSpeech = Task {
            if let cache = validCache { return PreparedSpeech(text: cache.text, pcm: cache.pcm, synthesisSeconds: cache.seconds, removedSilenceSeconds: 0) }
            return try await producer.next()
        }
        do {
            while let pending = nextSpeech {
                isWaitingForSpeech = true
                stage = metric.ttsFragments == 0 ? L10n.text("Готовлю озвучку…") : L10n.text("Готовлю следующую часть…")
                let wait = now
                guard let part = try await pending.value else { nextSpeech = nil; break }
                metric.speechQueueWaitSeconds += now - wait
                try check(id)
                metric.ttsSeconds += part.synthesisSeconds; metric.removedSilenceSeconds += part.removedSilenceSeconds
                do { try shareCache?.append(part.pcm) }
                catch { shareCache?.abort(); archiveWarning = L10n.text("Озвучка не сохранена: ") + error.localizedDescription }
                if let archive, let entry = savingID {
                    do { try await archive.appendAudio(part.pcm, to: entry) }
                    catch { await archive.abortAudio(entry); savingID = nil; archiveWarning = L10n.text("Озвучка не сохранена: ") + error.localizedDescription }
                }
                try check(id)
                // A single look-ahead task: current playback and at most one prepared PCM.
                nextSpeech = Task { try await producer.next() }
                if metric.playbackScheduledSeconds == nil { metric.playbackScheduledSeconds = now - start }
                stage = L10n.text("Озвучиваю…")
                isWaitingForSpeech = false
                try await player.play(part.pcm); try check(id)
                metric.spokenSeconds += Double(part.pcm.samples.count) / Double(part.pcm.sampleRate); metric.ttsFragments += 1
            }
            shareCache?.finish()
            if let archive, let entry = savingID {
                do {
                    try await archive.finishAudio(entry)
                    if archiveOriginal {
                        archivedOriginalSpeech[activeMode] = ArchivedSpeech(historyID: entry, text: text, language: target,
                            voice: files.voice(target), voiceModelID: files.voiceModelIDs[target])
                    } else {
                        archivedSpeech[activeMode] = speechIdentity(text: translatedText.trimmingCharacters(in: .whitespacesAndNewlines), language: target, files: files)
                    }
                }
                catch { await archive.abortAudio(entry); archiveWarning = L10n.text("Озвучка не сохранена: ") + error.localizedDescription }
            }
        } catch {
            nextSpeech?.cancel(); speech.cancel(); _ = await nextSpeech?.result; nextSpeech = nil
            shareCache?.abort()
            if let archive, let entry = savingID { await archive.abortAudio(entry) }
            throw error
        }
    }
    /// Return a private copy only when completed audio matches this exact field.
    /// Never synthesizes speech as a side effect of sharing.
    public func copyTextSpeechForSharing(text: String, language: SpeechLanguage, original: Bool, into directory: URL) async throws -> URL? {
        if let copy = try textSpeechShareCache.copy(text: text, language: language, original: original, into: directory) { return copy }
        let cached = original ? archivedOriginalSpeech[.text] : archivedSpeech[.text]
        guard let cached, cached.text == text.trimmingCharacters(in: .whitespacesAndNewlines), cached.language == language, let archive else { return nil }
        do { return try await archive.copyAudio(cached.historyID, into: directory) }
        catch HistoryError.missing { return nil }
    }
    public var hasVoiceTranslationSpeech: Bool {
        guard let language = voiceFields.resolvedTarget else { return false }
        return voiceSpeechShareCache.contains(text: voiceFields.translatedText, language: language, original: false)
    }
    /// Completed current Voice audio, independent of history and of the Text workspace.
    public func copyVoiceTranslationSpeech(into directory: URL) throws -> URL? {
        guard let language = voiceFields.resolvedTarget else { return nil }
        return try voiceSpeechShareCache.copy(text: voiceFields.translatedText, language: language, original: false, into: directory)
    }
    /// Call after cancellation/draining on exit; never removes recordings saved in history.
    public func clearTemporarySpeech() { textSpeechShareCache.clear(); voiceSpeechShareCache.clear(); voiceRecording.clear(); hasOriginalRecording = false }
    public func copyOriginalRecording(into directory: URL) throws -> URL? { try voiceRecording.copy(into: directory) }
    public func playOriginalRecording() async {
        guard !isBusy, unloading == nil, hasOriginalRecording else { return }
        activeMode = .voice
        generation += 1; let id = generation
        isBusy = true; isSpeaking = true; isPlayingOriginalRecording = true; isSpeechPaused = false
        error = nil; stage = L10n.text("Воспроизвожу запись…")
        let job = Task {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KatSpeechReplay").appendingPathComponent(UUID().uuidString)
            defer {
                player.stop(); isBusy = false; isSpeaking = false; isPlayingOriginalRecording = false
                isSpeechPaused = false; stage = ""; active = nil
                try? FileManager.default.removeItem(at: directory)
            }
            do {
                guard let file = try voiceRecording.copy(into: directory) else { throw HistoryError.missing }
                try check(id); player.setRate(Float(playbackSpeed.rawValue))
                try await player.play(file: file); try check(id)
            } catch is CancellationError {} catch { if id == generation { self.error = error.localizedDescription } }
        }
        active = job; await job.value
    }
    public func replay(mode: ConversationMode? = nil) async {
        let selectedMode = mode ?? activeMode
        let result = fields(for: selectedMode)
        guard let target = result.resolvedTarget else { return }
        await readAloud(result.translatedText, language: target, mode: selectedMode)
    }
    /// Reuse complete translated audio; first manual playback can attach audio to its existing history entry.
    /// Original speech has a separate history entry and never replaces translated audio.
    public func readAloud(_ text: String, language: SpeechLanguage, mode: ConversationMode? = nil, archiveOriginal: Bool = false) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, unloading == nil, let files, !text.isEmpty else { return }
        if let mode { activeMode = mode }
        generation += 1; let id = generation
        isBusy = true; error = nil; isSpeaking = true; isSpeechPaused = false; isWaitingForSpeech = false
        let job = Task {
            var metric = PipelineBenchmark(source: language.opposite, inputKind: "replay", inputMode: "replay", audioSeconds: nil, thermalState: "unknown", memorySaving: memorySaving)
            let start = now
            var originalEntry: UUID?
            defer { player.stop(); isSpeaking = false; isSpeechPaused = false; isWaitingForSpeech = false; isBusy = false; stage = ""; active = nil }
            do {
                try TranslationPrompt.validate(text)
                let identity: ArchivedSpeech?
                if archiveOriginal {
                    identity = archivedOriginalSpeech[activeMode].flatMap {
                        $0.text == text && $0.language == language && $0.voice == files.voice(language)
                            && $0.voiceModelID == files.voiceModelIDs[language] ? $0 : nil
                    }
                } else { identity = speechIdentity(text: text, language: language, files: files) }
                let cached = archiveOriginal ? archivedOriginalSpeech[activeMode] : archivedSpeech[activeMode]
                if let identity, cached == identity, let archive {
                    // A private copy survives retention/deletion and is removed after playback or cancellation.
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KatSpeechReplay").appendingPathComponent(UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let audio = try? await archive.copyAudio(identity.historyID, into: directory)
                    try check(id)
                    if let audio {
                        stage = L10n.text("Озвучиваю…")
                        player.setRate(Float(playbackSpeed.rawValue))
                        try await player.play(file: audio)
                        await releaseRecognitionIfRequested()
                        try check(id)
                        return
                    }
                }
                try check(id)
                if archiveOriginal, let archive {
                    do { originalEntry = try await archive.saveOriginalSpeech(text: text, language: language) }
                    catch { archiveWarning = L10n.text("Озвучка не сохранена: ") + error.localizedDescription }
                    try check(id)
                }
                try await speak(text, target: language, id: id, files: files, metric: &metric, start: start,
                    historyID: archiveOriginal ? originalEntry : identity?.historyID, archiveOriginal: archiveOriginal)
            }
            catch {
                if let archive, let entry = originalEntry { await archive.abortAudio(entry) }
                if !(error is CancellationError), id == generation { self.error = error.localizedDescription }
            }
            await releaseRecognitionIfRequested()
        }
        active = job; await job.value
    }
    public func cancel() {
        translationProgress = nil
        isSpeechPaused = false
        generation += 1
        if let preview = recordingPreview {
            preview.cancel()
            Task {
                await preview.waitForIdle()
                if recordingPreview === preview { recordingPreview = nil; isRecordingPreview = false; isBusy = false; stage = "" }
            }
        }
        active?.cancel(); nextSpeech?.cancel(); player.stop(); asr.cancel(); translator.cancel(); speech.cancel()
        if isBusy { stage = L10n.text("Останавливаю…") }
    }
    /// Clear both fields of one tab without touching the other tab, history or loaded models.
    public func clearFields(in mode: ConversationMode) {
        if activeMode == mode { cancel() }
        archivedSpeech[mode] = nil; archivedOriginalSpeech[mode] = nil
        switch mode {
        case .voice: voiceFields = ConversationFields(); voiceSpeechShareCache.clear(); voiceRecording.clear(); hasOriginalRecording = false
        case .text: textFields = ConversationFields(); textSpeechShareCache.clear()
        case .quick: quickFields = ConversationFields()
        }
    }
    /// Reclaim an inactive recognizer alongside a large translator without cancelling the turn.
    /// A busy backend is released only at the next safe pipeline boundary.
    public func relieveMemoryPressure() async -> Bool {
        if recognitionReleasePending { return true }
        guard unloading == nil, !isRecordingPreview,
              files?.translationModel.defersRecognitionLoading == true, asrLoaded else { return false }
        recognitionReleasePending = true
        if !isBusy {
            isBusy = true
            defer { isBusy = false }
            await releaseRecognitionIfRequested()
        }
        return true
    }
    private func releaseRecognitionIfRequested() async {
        guard recognitionReleasePending, unloading == nil else { return }
        // Keep isBusy and the request set across the await so another turn or warning
        // cannot race model teardown. Index and synthesized/shared audio stay intact.
        if asrLoaded {
            await asr.unload()
            asrLoaded = false; loadedASRURL = nil
        }
        recognitionReleasePending = false
    }

    public func unload() async {
        recognitionReleasePending = false
        if let unloading { await unloading.value; return }
        cancel(); isReady = false
        let work = active, preview = recordingPreview
        let job = Task {
            await preview?.waitForIdle()
            await work?.value
            isBusy = true; stage = L10n.text("Освобождаю память…")
            await asr.unload(); await translator.unload(); await speech.unload()
            asrLoaded = false; loadedASRURL = nil; mtLoaded = false; voiceLoaded = nil; isBusy = false; stage = ""; unloading = nil
        }
        unloading = job; await job.value
    }
}


public extension ConversationPipeline {
    func finishRecordingTelemetry(footprint: UInt64, resident: UInt64, thermal: String) {
        guard !samples.isEmpty else { return }
        samples[samples.count - 1].peakFootprintBytes = footprint
        samples[samples.count - 1].peakResidentBytes = resident
        samples[samples.count - 1].endThermalState = thermal
    }
    func recordingPreviewUnavailable(source: SpeechLanguage?) -> String? {
        guard let files, [.index9B, .qwen9B].contains(files.translationModel) else { return "model" }
        if memorySaving { return "memory-saving" }
        if let source, source.whisperCode == nil { return "recognizer" }
        return nil
    }
    func beginRecordingPreview(source: SpeechLanguage?, target: SpeechLanguage, speakResult: Bool,
                               snapshot: @escaping RecordingPreviewCoordinator.Snapshot) -> Bool {
        guard isReady, !isBusy, unloading == nil, recordingPreviewUnavailable(source: source) == nil, let files else { return false }
        generation += 1; let id = generation
        isBusy = true; isRecordingPreview = true; activeMode = .voice
        voiceFields = ConversationFields() // Capture is already active; do not deactivate its audio session.
        let prepareAudio: (@MainActor (String, SpeechLanguage) async throws -> RecordingPreviewSpeech?)?
        if speakResult { prepareAudio = { [weak self] text, target in
                guard let self, let voice = files.voice(target) else { return nil }
                try self.check(id)
                if self.voiceLoaded != target { self.voiceLoaded = nil; try await self.speech.load(directory: voice, language: target); self.voiceLoaded = target }
                try self.check(id)
                let producer = try SpeechPreparation(text: text, speech: self.speech)
                guard let part = try await producer.next() else { return nil }
                try self.check(id)
                return RecordingPreviewSpeech(text: part.text, pcm: part.pcm, seconds: part.synthesisSeconds)
            } } else { prepareAudio = nil }
        recordingPreview = RecordingPreviewCoordinator(source: source, target: target, snapshot: snapshot,
            recognize: { [weak self] audio, language in
                guard let self else { throw CancellationError() }
                try self.check(id)
                let recognitionURL = try files.recognitionURL(for: language)
                if self.asrLoaded, self.loadedASRURL != recognitionURL { await self.asr.unload(); self.asrLoaded = false }
                try self.check(id)
                if !self.asrLoaded { try await self.asr.load(modelURL: recognitionURL); self.asrLoaded = true; self.loadedASRURL = recognitionURL }
                try self.check(id)
                return try await self.asr.transcribe(audio, language: language)
            }, translate: { [weak self] text, source, target in
                guard let self else { throw CancellationError() }
                try self.check(id)
                if source == target { return TranslationResult(text: text, firstTokenSeconds: nil, processingSeconds: 0, fragments: 1) }
                let resolved = try await self.resolveTranslation(self.files ?? files, source: source, target: target, generation: id)
                if !self.mtLoaded { try await self.translator.load(modelURL: resolved.translation, model: resolved.translationModel); self.mtLoaded = true }
                try self.check(id)
                let result = try await self.translator.translate(text: text, source: source, target: target)
                try self.check(id)
                return result
            }, prepareSpeech: prepareAudio, publish: { [weak self] result in
                guard let self, self.generation == id else { return }
                self.voiceFields.sourceText = result.sourceText; self.voiceFields.translatedText = result.translatedText
                self.voiceFields.resolvedSource = result.source; self.voiceFields.resolvedTarget = result.target
            })
        return true
    }
    func offerRecordingBoundary(_ end: Int) { recordingPreview?.offer(end: end) }
    func suspendRecordingPreview(reason: String) { recordingPreview?.suspend(reason: reason) }
    func runRecording(audio: CapturedAudio, speechEnd: Int, source: SpeechLanguage?, target: SpeechLanguage,
                      speakResult: Bool, inputMode: String, thermal: String, stoppedAt: Double,
                      requestedPreview: Bool, fallbackReason: String?, verifyPreview: Bool = false) async {
        let id = generation
        let preview = recordingPreview
        let prepared = await preview?.finish()
        guard id == generation else { return }
        if preview != nil { recordingPreview = nil; isRecordingPreview = false; isBusy = false }
        let committed = min(audio.samples.count, prepared?.committedSamples ?? 0)
        // No tail ASR on the silence that follows the final committed phrase.
        let tail = committed > 0 && speechEnd <= committed ? [] : Array(audio.samples.dropFirst(committed))
        let verifying = verifyPreview && (prepared?.blocks ?? 0) > 0
        await run(audio: verifying ? audio : CapturedAudio(samples: tail), source: source, target: target, speakResult: speakResult,
                  inputMode: inputMode, thermal: thermal, preview: prepared, stoppedAt: stoppedAt,
                  recordedSeconds: audio.durationSeconds, processingMode: preview == nil ? (requestedPreview ? "preview-fallback" : "after-stop") : (verifying ? "during-recording-verified" : "during-recording"),
                  fallbackReason: fallbackReason, verifyPreview: verifying, originalRecording: audio)
    }
}

/// Speaks finished sentences of a translation that is still being generated, in order.
/// The translation text is unchanged; only the moment speech starts moves earlier.
@MainActor final class StreamedSpeechStart {
    private(set) var startedAt: Double?
    private(set) var spokenText = ""
    private var pcm: [Float] = []
    private var sampleRate = 0
    private var synthesisSeconds = 0.0
    private var chunks: [String] = []
    private var claimed = 0
    private var closed = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var worker: Task<Void, Never>?
    var started: Bool { worker != nil }
    var speech: RecordingPreviewSpeech? {
        spokenText.isEmpty ? nil : RecordingPreviewSpeech(text: spokenText, pcm: SpeechPCM(samples: pcm, sampleRate: sampleRate), seconds: synthesisSeconds)
    }
    /// Finished sentences of `text` (each followed by more text), grouped to at least 12 characters.
    nonisolated static func sentences(in text: String, from offset: Int = 0) -> (chunks: [String], end: Int) {
        let characters = Array(text)
        var chunks: [String] = [], start = offset, end = offset
        guard offset < characters.count else { return ([], offset) }
        for index in offset..<max(offset, characters.count - 1) where ".!?…".contains(characters[index]) && characters[index + 1].isWhitespace {
            let candidate = String(characters[start...index]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count > 180 { break }
            if candidate.count >= 12 { chunks.append(candidate); start = index + 1; end = index + 1 }
        }
        return (chunks, end)
    }
    nonisolated static func firstSentence(of text: String) -> String? { sentences(in: text).chunks.first }
    func offer(_ partial: String, prepare: @escaping @MainActor (String) async throws -> RecordingPreviewSpeech?,
               play: @escaping @MainActor (RecordingPreviewSpeech) -> Task<Void, Error>) {
        guard !closed else { return }
        let found = Self.sentences(in: partial, from: claimed)
        guard !found.chunks.isEmpty else { return }
        claimed = found.end; chunks += found.chunks
        if let waiting { self.waiting = nil; waiting.resume() }
        if worker == nil { worker = Task { [weak self] in await self?.run(prepare: prepare, play: play) } }
    }
    private func next() async -> String? {
        while chunks.isEmpty && !closed { await withCheckedContinuation { waiting = $0 } }
        return chunks.isEmpty ? nil : chunks.removeFirst()
    }
    private func run(prepare: @escaping @MainActor (String) async throws -> RecordingPreviewSpeech?,
                     play: @escaping @MainActor (RecordingPreviewSpeech) -> Task<Void, Error>) async {
        var playing: Task<Void, Error>?
        // The next sentence is synthesized while the previous one plays.
        while let chunk = await next(), !Task.isCancelled {
            guard let prepared = try? await prepare(chunk), !Task.isCancelled else { break }
            if let playing { guard (try? await playing.value) != nil else { return } }
            guard sampleRate == 0 || sampleRate == prepared.pcm.sampleRate else { break }
            if startedAt == nil { startedAt = ProcessInfo.processInfo.systemUptime }
            sampleRate = prepared.pcm.sampleRate; pcm += prepared.pcm.samples; synthesisSeconds += prepared.seconds
            spokenText = spokenText.isEmpty ? prepared.text : spokenText + " " + prepared.text
            playing = play(prepared)
        }
        _ = try? await playing?.value
    }
    /// Stops taking new sentences and waits until the queued ones have been spoken.
    func finish() async {
        closed = true
        if let waiting { self.waiting = nil; waiting.resume() }
        await worker?.value
    }
    func cancel() { closed = true; waiting?.resume(); waiting = nil; worker?.cancel() }
}
