import Foundation
import Combine
import OfflineCore

@MainActor final class PackageDownloadCoordinator: ObservableObject {
    static let shared = PackageDownloadCoordinator()
    let whisper = ModelDownloader.shared
    let recognition = RecognitionPackages()
    let opus = OpusPackage()
    let opusDirections = OpusDirectionPackages()
    let index2B = ModelDownloader(model: SharedModelAssets.indexTranslation2B)
    func primaryRecognition(for preference: RecognitionPreference) -> URL? { whisper.installedURL }
    let omnilingual = ModelDownloader(model: ModelCatalog.omnilingual)
    var omnilingualDirectory: URL? { voiceDirectories[omnilingual.model.id] }
    let balineseVoice = ModelDownloader(model: ModelCatalog.balineseVoice)
    let balineseTokens = ModelDownloader(model: ModelCatalog.balineseTokens)
    var balineseComponents: [ModelDownloader] { [balineseVoice, balineseTokens] }
    let additionalVoices = AdditionalVoiceCatalog.catalog.packages.flatMap { $0.models.map { ModelDownloader(model: $0) } }
    private func additionalParts(_ definition: VoicePackageDefinition) -> [ModelDownloader] {
        definition.parts.compactMap { part in additionalVoices.first { $0.model.id == part.id } }
    }
    private func packageOwner(_ item: ModelDownloader) -> ModelDownloader {
        if let definition = AdditionalVoiceCatalog.catalog.package(containing: item.model.id),
           let owner = additionalParts(definition).first { return owner }
        if balineseComponents.contains(where: { $0 === item }) { return balineseVoice }
        if wayuComponents.contains(where: { $0 === item }) { return wayuVoice }
        return item
    }
    #if os(macOS)
    let indexMLX = MacIndexPackage()
    var indexTranslation: ModelDownloader { indexMLX.downloaders[0] }
    #else
    let indexTranslation = ModelDownloader(model: ModelCatalog.indexTranslation)
    #endif
    @Published private(set) var selectedTranslation = TranslationModel.restoredSelection(UserDefaults.standard.string(forKey: "selectedTranslationModel"))
    func singleFileTranslation(_ choice: TranslationModel) -> ModelDownloader? {
        switch choice {
        case .opusBig: return nil
        case .index9B: return indexTranslation
        case .index2B: return index2B
        case .opusDirections, .gemma4B, .qwen9B, .mil4B, .mil12B: return nil
        }
    }
    var translationURL: URL? { translationURL(for: selectedTranslation) }
    func translationURL(for choice: TranslationModel) -> URL? {
        #if os(macOS)
        if choice == .index9B { return indexMLX.directory }
        #endif
        if choice == .opusDirections { return opusDirections.directories.isEmpty ? nil : ModelDownloader.root.appendingPathComponent("TranslationPackages") }
        return choice == .opusBig ? opus.directory : singleFileTranslation(choice)?.installedURL
    }
    func translationFiles(_ choice: TranslationModel) -> [ModelDownloader] {
        #if os(macOS)
        if choice == .index9B { return indexMLX.downloaders }
        #endif
        return choice == .opusBig ? opus.downloaders : singleFileTranslation(choice).map { [$0] } ?? []
    }
    func translationBytes(_ choice: TranslationModel) -> Int64 {
        #if os(macOS)
        if choice == .index9B { return MacIndexPackage.bytes }
        #endif
        return choice == .opusBig ? OpusPackage.bytes : singleFileTranslation(choice)?.model.byteCount ?? 0
    }
    var translationDownloaders: [ModelDownloader] {
        #if os(macOS)
        return indexMLX.downloaders + [index2B]
        #else
        return [indexTranslation, index2B]
        #endif
    }
    /// Auto: the model follows the language pair and the device check (see AutoTranslation).
    @Published private(set) var autoTranslation: Bool = UserDefaults.standard.object(forKey: AutoTranslation.preferenceKey) as? Bool
        ?? (UserDefaults.standard.string(forKey: "selectedTranslationModel") == nil)
    func setAutoTranslation(_ value: Bool) { autoTranslation = value; UserDefaults.standard.set(value, forKey: AutoTranslation.preferenceKey) }
    var strongDevice: Bool { DeviceProbe.saved?.strong ?? false }
    func resolvedTranslation(source: SpeechLanguage, target: SpeechLanguage) -> TranslationModel? {
        AutoTranslation.resolve(source: source, target: target, strongDevice: strongDevice,
                                installed: { self.translationURL(for: $0) != nil },
                                directionInstalled: { self.opusDirections.installedRoute($0, $1) != nil })
    }
    var translationResolver: TranslationResolver? {
        guard autoTranslation else { return nil }
        return { [weak self] source, target in
            guard let self, let model = self.resolvedTranslation(source: source, target: target),
                  let url = self.translationURL(for: model) else { throw PipelineError.modelLanguageUnavailable }
            self.selectTranslation(model)
            return TranslationInstallation(model: model, url: url)
        }
    }
    /// Translation part of a setup in Auto: Index 9B on powerful devices; otherwise OPUS per pair
    /// (English package or both direction packages), and Index 2B for pairs OPUS cannot cover.
    func autoPlan(_ setup: LanguageSetup) -> (models: [TranslationModel], directions: [OpusDirectionPackage]) {
        if strongDevice { return ([.index9B], []) }
        var models: [TranslationModel] = [], directions: [OpusDirectionPackage] = []
        for target in setup.targetIDs where target != setup.primaryID {
            guard let a = SpeechLanguage(rawValue: setup.primaryID), let b = SpeechLanguage(rawValue: target) else { continue }
            if TranslationModel.opusBig.supports(source: a, target: b) { models.append(.opusBig); continue }
            let pair = [(a.rawValue, b.rawValue), (b.rawValue, a.rawValue)].map { (opusDirections.installedRoute($0.0, $0.1) ?? OpusDirectionRoutes.route($0.0, $0.1, available: { $0.hosted }).flatMap { opusDirections.package($0.packageID) }) }
            if pair.allSatisfy({ $0 != nil && ($0!.directory != nil || $0!.route.hosted) }) { directions += pair.compactMap { $0 } }
            else { models.append(.index2B) }
        }
        if models.isEmpty && directions.isEmpty { models = [.index2B] }
        var seen = Set<String>()
        return (models.filter { seen.insert($0.rawValue).inserted }, directions.filter { seen.insert($0.id).inserted })
    }
    var translationTermsAccepted: Bool { !selectedTranslation.requiresGemmaTerms || gemmaAccepted }
    func selectTranslation(_ model: TranslationModel) {
        guard TranslationModel.selectable.contains(model) else { return }
        selectedTranslation = model
        UserDefaults.standard.set(model.rawValue, forKey: "selectedTranslationModel")
    }
    let russianVoice = ModelDownloader(model: ModelCatalog.russianVoice)
    let englishVoice = ModelDownloader(model: ModelCatalog.englishVoice)
    let irinaVoice = ModelDownloader(model: ModelCatalog.irinaVoice)
    let lessacVoice = ModelDownloader(model: ModelCatalog.lessacVoice)
    let supertonicVoice = ModelDownloader(model: ModelCatalog.supertonicVoice)
    let chineseVoice = ModelDownloader(model: ModelCatalog.chineseVoice)
    let wayuVoice = ModelDownloader(model: ModelCatalog.wayuVoice)
    let wayuCurves = ModelDownloader(model: ModelCatalog.wayuCurves)
    let wayuDecoder = ModelDownloader(model: ModelCatalog.wayuDecoder)
    let wayuStyles = ModelDownloader(model: ModelCatalog.wayuStyles)
    var wayuComponents: [ModelDownloader] { [wayuVoice, wayuCurves, wayuDecoder, wayuStyles] }
    func components(_ item: ModelDownloader) -> [ModelDownloader] {
        if let definition = AdditionalVoiceCatalog.catalog.package(containing: item.model.id) { return additionalParts(definition) }
        return packageOwner(item) === wayuVoice ? wayuComponents : packageOwner(item) === balineseVoice ? balineseComponents : [item]
    }
    let ocrRussian = ModelDownloader(model: ModelCatalog.ocrRussian)
    let ocrEnglish = ModelDownloader(model: ModelCatalog.ocrEnglish)
    func ocr(_ language: SpeechLanguage) -> ModelDownloader? { language == .russian ? ocrRussian : language == .english ? ocrEnglish : nil }
    private var validationDownloaders: [ModelDownloader] {
        #if DOWNLOAD_VALIDATION
        return DownloadValidationProbe.items
        #else
        return []
        #endif
    }
    var downloaders: [ModelDownloader] { [whisper, omnilingual, balineseVoice, balineseTokens] + translationDownloaders + opusDirections.downloaders + [russianVoice, englishVoice, irinaVoice, lessacVoice, supertonicVoice, chineseVoice, wayuVoice, wayuCurves, wayuDecoder, wayuStyles, ocrRussian, ocrEnglish] + additionalVoices + recognition.downloaders + opus.downloaders + validationDownloaders }
    var requiredDownloaders: [ModelDownloader] { translationFiles(selectedTranslation) }
    func voices(_ language: SpeechLanguage) -> [ModelDownloader] {
        let additional = AdditionalVoiceCatalog.catalog.voices(language: language.rawValue).compactMap { definition in
            additionalVoices.first { $0.model.id == definition.id }
        }
        switch language {
        // Irina is the default Russian voice; Denis stays available as an option.
        case .russian: return [irinaVoice, russianVoice, supertonicVoice] + additional
        case .english: return [englishVoice, lessacVoice, supertonicVoice] + additional
        case .chinese: return [chineseVoice] + additional
        case .thai: return [wayuVoice] + additional
        case .lang_ban: return [balineseVoice] + additional
        default:
            let supertonicLanguages: Set<String> = ["ar", "de", "es", "fr", "hi", "it", "ja", "ko", "pt", "tr", "nl", "pl", "ro", "sv", "vi", "id", "uk", "cs", "el", "da", "hu", "fi", "sk", "bg", "lt", "sl", "et", "lv", "hr"]
            return (supertonicLanguages.contains(language.rawValue) ? [supertonicVoice] : []) + additional
        }
    }
    var selectedVoiceDirectories: [SpeechLanguage: URL] {
        Dictionary(uniqueKeysWithValues: SpeechLanguage.allCases.filter(\.hasVoice).compactMap { language in
            voiceDirectories[selectedVoice(language).model.id].map { directory in
                if selectedVoice(language) === wayuVoice {
                    var url = URLComponents(url: directory, resolvingAgainstBaseURL: false)!
                    url.fragment = "wayu:" + WayuVoice.selected.rawValue
                    return (language, url.url!)
                }
                if selectedVoice(language).model.id == "omnivoice-q8-base" {
                    var url = URLComponents(url: directory, resolvingAgainstBaseURL: false)!
                    url.fragment = "omni:" + language.rawValue
                    return (language, url.url!)
                }
                return (language, directory)
            }
        })
    }
    var selectedVoiceModelIDs: [SpeechLanguage: String] {
        Dictionary(uniqueKeysWithValues: selectedVoiceDirectories.keys.map { ($0, selectedVoice($0).model.id + (selectedVoice($0) === wayuVoice ? ":" + WayuVoice.selected.rawValue : "")) })
    }
    var readyVoiceLanguageCount: Int { selectedVoiceDirectories.count }
    var missingVoiceDownloaders: [ModelDownloader] {
        var seen = Set<String>()
        return SpeechLanguage.allCases.filter(\.hasVoice).flatMap { components(selectedVoice($0)) }.filter {
            voiceDirectories[$0.model.id] == nil && seen.insert($0.model.id).inserted
        }
    }
    var missingVoiceBytes: Int64 { missingVoiceDownloaders.filter { $0.installedURL == nil }.reduce(0) { $0 + $1.model.byteCount } }
    func selectedVoice(_ language: SpeechLanguage) -> ModelDownloader {
        let id = UserDefaults.standard.string(forKey: "voice." + language.rawValue)
        if let chosen = voices(language).first(where: { $0.model.id == id }) { return chosen }
        // Without an explicit choice keep a voice that is already installed (an earlier default),
        // so changing the default never leaves an existing user without speech.
        if voiceDirectories[voices(language)[0].model.id] == nil,
           let installed = voices(language).first(where: { voiceDirectories[$0.model.id] != nil }) { return installed }
        return voices(language)[0]
    }
    func selectVoice(_ item: ModelDownloader, language: SpeechLanguage) {
        guard voiceDirectories[item.model.id] != nil, voices(language).contains(where: { $0 === item }) else { return }
        objectWillChange.send(); UserDefaults.standard.set(item.model.id, forKey: "voice." + language.rawValue)
    }
    func downloadVoice(_ item: ModelDownloader) {
        guard restored, !translationDownloaders.contains(where: { $0 === item }), item !== whisper else { return }
        if components(item).count > 1 { startVoiceQueue(components(item)); return }
        DownloadNotifications.started(packageOwner(item).model.id)
        if item.installedURL != nil { prepareVoice(item) }
        else { item.start(resuming: item.state.phase == .paused) }
    }
    @Published private(set) var voiceDirectories: [String: URL] = [:]
    @Published private(set) var installing = Set<String>()
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var downloadingAll = false
    @Published private(set) var downloadingVoices = false
    @Published private(set) var voiceQueueItems: [ModelDownloader] = []
    var voiceQueueTotalBytes: Int64 { voiceQueueItems.reduce(0) { $0 + $1.model.byteCount } }
    var voiceQueueReceivedBytes: Int64 {
        voiceQueueItems.reduce(0) { $0 + ($1.installedURL != nil ? $1.model.byteCount : min($1.state.receivedBytes, $1.model.byteCount)) }
    }
    var voiceQueueStatus: String {
        if voiceQueueItems.contains(where: { installing.contains($0.model.id) || $0.state.phase == .checking }) { return L10n.text("Проверяю файлы голоса…") }
        return L10n.text("Скачиваю голоса…")
    }
    @Published private(set) var restored = false
    @Published var gemmaAccepted = UserDefaults.standard.bool(forKey: "gemmaTermsAccepted") {
        didSet { UserDefaults.standard.set(gemmaAccepted, forKey: "gemmaTermsAccepted") }
    }
    private let store = PackageStore(root: ModelDownloader.root.appendingPathComponent("VoicePackages"), onUncachedVerification: ModelVerificationStatus.changed)
    private var manifests: [String: ModelPackage] = [:]
    private var jobs: [String: Task<Void, Never>] = [:]
    private var voiceQueueTask: Task<Void, Never>?
    private var queueTask: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()
    private var restoreJob: Task<Void, Never>?
    var ready: Bool { translationURL != nil }
    func downloadPackageFailed(_ item: ModelDownloader) -> Bool {
        #if os(macOS)
        if indexMLX.contains(item) { return indexMLX.error != nil }
        #endif
        if opus.contains(item) { return opus.error != nil }
        if let package = opusDirections.package(containing: item) { return package.error != nil }
        if let definition = RecognitionPackages.definitions.first(where: { $0.parts.contains { $0.id == item.model.id } }) { return recognition.errors[definition.id] != nil }
        return errors[packageOwner(item).model.id] != nil
    }
    func downloadReady(_ item: ModelDownloader) -> Bool {
        #if os(macOS)
        if indexMLX.contains(item) { return indexMLX.directory != nil }
        #endif
        if opus.contains(item) { return opus.directory != nil }
        if let package = opusDirections.package(containing: item) { return package.directory != nil }
        guard item.installedURL != nil else { return false }
        if let definition = RecognitionPackages.definitions.first(where: { $0.parts.contains { $0.id == item.model.id } }) {
            return recognition.directories[definition.id] != nil
        }
        let owner = packageOwner(item).model.id
        if manifests[owner] != nil || wayuComponents.contains(where: { $0 === item }) { return voiceDirectories[owner] != nil }
        return true
    }
    func canSpeak(_ language: SpeechLanguage) -> Bool { language.hasVoice && voiceDirectories[selectedVoice(language).model.id] != nil }
    private init() {
        let defaults = UserDefaults.standard
        RetiredTranslationModels.migratePreferences(defaults)
        defaults.set(RecognitionPreference.restoredSelection(defaults.string(forKey: "recognitionPreference")).rawValue, forKey: "recognitionPreference")
        #if os(macOS)
        indexMLX.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        #endif
        opus.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        opusDirections.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        recognition.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        do {
            guard let url = Bundle.main.url(forResource: "voice-manifests", withExtension: "json") else { throw PackageError.incomplete }
            let list = try JSONDecoder().decode([ModelPackage].self, from: Data(contentsOf: url))
            manifests = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch { errors["catalog"] = error.localizedDescription }
        for downloader in downloaders {
            downloader.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send(); DownloadLiveActivity.changed() }.store(in: &observers)
            downloader.$installedURL.dropFirst().sink { [weak self, weak downloader] url in
                guard url != nil, let self, let downloader else { return }
                // Published delivers before installedURL is assigned; install on the next actor turn.
                Task { @MainActor [weak self, weak downloader] in
                    guard let self, let downloader else { return }
                    self.prepareVoice(downloader)
                }
            }.store(in: &observers)
        }
    }
    func reportRetiredVoiceError(_ error: Error) {
        errors[ModelCatalog.wayuVoice.id] = L10n.text("Не удалось удалить старый тайский голос: \(error.localizedDescription)")
    }
    func reportRetiredRecognitionError(_ error: Error) {
        errors[RetiredWhisperKit.id] = error.localizedDescription
    }
    func reportRetiredTranslationError(_ error: Error) {
        errors["retiredTranslationModels"] = error.localizedDescription
    }
    func restore() async {
        if let restoreJob { await restoreJob.value; return }
        let job = Task {
            ModelVerificationStatus.shared.beginRestoration()
            defer { ModelVerificationStatus.shared.endRestoration() }
            await removeRetiredTranslationModels()
            await removeRetiredThaiVoice()
            await removeRetiredWhisperKit()
            for downloader in downloaders { await downloader.restore(); prepareVoice(downloader) }
            for job in jobs.values { await job.value }
            await recognition.restore()
            await opus.restore()
            await opusDirections.restore()
            #if os(macOS)
            await indexMLX.restore()
            #endif
            restored = true
            if UserDefaults.standard.bool(forKey: "downloadAllPending") { startAll() }
            if let pending = UserDefaults.standard.stringArray(forKey: "pendingVoiceIDs") {
                startVoiceQueue(pending.compactMap { id in downloaders.first { $0.model.id == id } })
            }
        }
        restoreJob = job; await job.value
    }
    func finishBackgroundDownload(_ downloader: ModelDownloader) async {
        #if os(macOS)
        if indexMLX.contains(downloader) { for item in indexMLX.downloaders { await item.restore() }; await indexMLX.assembleIfComplete(); return }
        #endif
        if opus.contains(downloader) {
            for item in opus.downloaders { await item.restore() }
            await opus.assembleIfComplete(); DownloadLiveActivity.changed(); return
        }
        if let package = opusDirections.package(containing: downloader) {
            for item in package.downloaders { await item.restore() }
            await package.assembleIfComplete(); DownloadLiveActivity.changed(); return
        }
        // Reattach only this package after a system relaunch. Revalidating every
        // installed model here can exhaust the finite background execution window.
        let definition = RecognitionPackages.definitions.first { $0.parts.contains { $0.id == downloader.model.id } }
        let related = definition.map { recognition.parts($0) } ?? components(downloader)
        for item in related { await item.restore() }
        prepareVoice(downloader)
        if let job = jobs[packageOwner(downloader).model.id] { await job.value }
        await recognition.assembleCompletedPackages()
        DownloadLiveActivity.changed()
    }
    private func prepareVoice(_ downloader: ModelDownloader) {
        #if os(macOS)
        if indexMLX.contains(downloader) { Task { await indexMLX.assembleIfComplete() }; return }
        #endif
        if opus.contains(downloader) { Task { await opus.assembleIfComplete() }; return }
        if let package = opusDirections.package(containing: downloader) { Task { await package.assembleIfComplete() }; return }
        if let definition = AdditionalVoiceCatalog.catalog.package(containing: downloader.model.id), definition.kind != .archive {
            let id = definition.id
            let parts = additionalParts(definition)
            guard let package = manifests[id], parts.allSatisfy({ $0.installedURL != nil }),
                  jobs[id] == nil, voiceDirectories[id] == nil else { return }
            let files = Dictionary(uniqueKeysWithValues: zip(definition.parts, parts).map { ($0.0.path, $0.1.installedURL!) })
            installing.insert(id); errors[id] = nil
            jobs[id] = Task {
                let background = DownloadBackgroundWork()
                defer { background.end() }
                defer { installing.remove(id); jobs[id] = nil; DownloadLiveActivity.changed() }
                do {
                    let ready = try await store.readyDirectory(for: package)
                    let directory: URL
                    if let ready { directory = ready }
                    else if let preparation = definition.piperPreparation, let model = files["model.onnx"] {
                        directory = try await store.installPiper(model: model, preparation: preparation, package: package)
                    } else { directory = try await store.install(files: files, package: package) }
                    try Task.checkCancellation()
                    for part in parts { voiceDirectories[part.model.id] = directory }
                    DownloadLiveActivity.changed()
                    await DownloadNotifications.ready(id, title: downloader.model.title)
                } catch is CancellationError {} catch { errors[id] = error.localizedDescription }
            }
            return
        }
        if balineseComponents.contains(where: { $0 === downloader }) {
            let id = balineseVoice.model.id
            guard let package = manifests[id], let model = balineseVoice.installedURL, let tokens = balineseTokens.installedURL,
                  jobs[id] == nil, voiceDirectories[id] == nil else { return }
            installing.insert(id); errors[id] = nil
            jobs[id] = Task {
                let background = DownloadBackgroundWork()
                defer { background.end() }
                defer { installing.remove(id); jobs[id] = nil; DownloadLiveActivity.changed() }
                do {
                    let ready = try await store.readyDirectory(for: package)
                    let directory: URL
                    if let ready { directory = ready }
                    else { directory = try await store.install(files: ["model.onnx": model, "tokens.txt": tokens], package: package) }
                    try Task.checkCancellation()
                    for item in balineseComponents { voiceDirectories[item.model.id] = directory }
                    DownloadLiveActivity.changed()
                    await DownloadNotifications.ready(id, title: balineseVoice.model.title)
                } catch is CancellationError {} catch { errors[id] = error.localizedDescription }
            }
            return
        }
        let id = downloader.model.id
        if wayuComponents.contains(where: { $0 === downloader }) {
            if wayuComponents.allSatisfy({ $0.installedURL != nil }), let directory = wayuVoice.installedURL?.deletingLastPathComponent() {
                for item in wayuComponents { voiceDirectories[item.model.id] = directory }
                Task { DownloadLiveActivity.changed()
                    await DownloadNotifications.ready(wayuVoice.model.id, title: wayuVoice.model.title) }
            }
            return
        }
        guard let package = manifests[id], let archive = downloader.installedURL, jobs[id] == nil, voiceDirectories[id] == nil else { return }
        installing.insert(id); errors[id] = nil
        jobs[id] = Task {
            let background = DownloadBackgroundWork()
            defer { background.end() }
            defer { installing.remove(id); jobs[id] = nil; DownloadLiveActivity.changed() }
            do {
                let ready = try await store.readyDirectory(for: package)
                let directory: URL
                if let ready { directory = ready }
                else { directory = try await store.install(archive: archive, package: package) }
                try Task.checkCancellation(); voiceDirectories[id] = directory
                DownloadLiveActivity.changed()
                await DownloadNotifications.ready(id, title: downloader.model.title)
            } catch is CancellationError { }
            catch { errors[id] = error.localizedDescription }
        }
    }
    #if os(macOS)
    func startIndexMLX() {
        guard restored, checkDownloadSpace(indexMLX.requirements) else { return }
        indexMLX.start()
    }
    #endif
    func startOpus() {
        guard restored, checkDownloadSpace(opus.requirements) else { return }
        opus.start()
    }
    /// Hosted direction packages chosen in the OPUS directions screen.
    func startOpusDirections(_ packages: [OpusDirectionPackage]) {
        guard restored, checkDownloadSpace(packages.flatMap(\.requirements)) else { return }
        for package in packages { package.start() }
    }
    func startAll() {
        guard translationTermsAccepted, !downloadingAll, restored else { return }
        let setup = activeDownloadSetup
        guard checkDownloadSpace(setupRequirements(setup, model: selectedTranslation)) else { return }
        downloadingAll = true; UserDefaults.standard.set(true, forKey: "downloadAllPending")
        let required = setupFiles(setup, model: selectedTranslation)
        if required.contains(where: opus.contains) { DownloadNotifications.started(TranslationModel.opusBig.rawValue) }
        for item in required where item.installedURL == nil {
            if !opus.contains(item) { DownloadNotifications.started(packageOwner(item).model.id) }
            item.start(resuming: item.state.phase == .paused)
        }
        recognition.start(ids: Array(setup.recognitionIDs))
        queueTask = Task {
            defer { downloadingAll = false; queueTask = nil; UserDefaults.standard.set(false, forKey: "downloadAllPending") }
            await recognition.waitForDownloads()
            guard !Task.isCancelled, setup.recognitionIDs.filter({ $0 != LanguageSetup.omnilingualID && $0 != ModelDescriptor.turbo.id }).allSatisfy({ recognition.directories[$0] != nil }) else { return }
            for downloader in required {
                guard !Task.isCancelled else { return }
                if downloader.installedURL == nil {
                    if downloader.state.phase != .downloading && downloader.state.phase != .checking {
                        downloader.start(resuming: downloader.state.phase == .paused)
                    }
                    while downloader.state.phase == .downloading || downloader.state.phase == .checking || downloader.isManaging {
                        do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                    }
                    guard downloader.installedURL != nil else { return }
                }
                prepareVoice(downloader)
                if opus.contains(downloader) { await opus.assembleIfComplete() }
                if let package = opusDirections.package(containing: downloader) { await package.assembleIfComplete() }
                #if os(macOS)
                if indexMLX.contains(downloader) { await indexMLX.assembleIfComplete() }
                #endif
                let owner = packageOwner(downloader).model.id
                if let job = jobs[owner] { await job.value }
                if errors[owner] != nil { return }
            }
        }
    }
    private func checkDownloadSpace(_ files: [DownloadRequirement]) -> Bool {
        errors["downloadSpace"] = nil
        let required = DownloadRequirement.missingBytes(files) * 2 + 256 * 1024 * 1024
        if let available = try? ModelDownloader.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, available < required {
            errors["downloadSpace"] = L10n.text("Нужно \(L10n.bytes(required)) свободного места; доступно \(L10n.bytes(Int64(available))).")
            return false
        }
        return true
    }
    func startAllVoices() {
        startVoiceQueue(missingVoiceDownloaders)
    }
    private func startVoiceQueue(_ items: [ModelDownloader]) {
        guard restored, !items.isEmpty, checkDownloadSpace(items.map { DownloadRequirement(id: $0.model.id, bytes: $0.model.byteCount, installed: $0.installedURL != nil) }) else { return }
        for item in items where item.installedURL == nil {
            DownloadNotifications.started(packageOwner(item).model.id)
            item.start(resuming: item.state.phase == .paused)
        }
        if downloadingVoices {
            for item in items where !voiceQueueItems.contains(where: { $0 === item }) { voiceQueueItems.append(item) }
            UserDefaults.standard.set(voiceQueueItems.map { $0.model.id }, forKey: "pendingVoiceIDs")
            return
        }
        voiceQueueItems = items
        downloadingVoices = true; UserDefaults.standard.set(items.map { $0.model.id }, forKey: "pendingVoiceIDs")
        voiceQueueTask = Task {
            defer { downloadingVoices = false; voiceQueueTask = nil; UserDefaults.standard.removeObject(forKey: "pendingVoiceIDs") }
            var index = 0
            while index < voiceQueueItems.count {
                let item = voiceQueueItems[index]; index += 1
                guard !Task.isCancelled else { return }
                if item.installedURL == nil {
                    if item.state.phase != .downloading && item.state.phase != .checking && !item.isManaging {
                        item.start(resuming: item.state.phase == .paused)
                    }
                    while item.state.phase == .downloading || item.state.phase == .checking || item.isManaging {
                        do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                    }
                    guard item.installedURL != nil else { return }
                }
                prepareVoice(item)
                if let job = jobs[packageOwner(item).model.id] { await job.value }
                guard errors[packageOwner(item).model.id] == nil, item.installedURL != nil else { return }
            }
        }
    }
    func pauseVoiceDownloads() async {
        voiceQueueTask?.cancel(); await voiceQueueTask?.value
        for item in ([russianVoice, englishVoice, irinaVoice, lessacVoice, supertonicVoice, chineseVoice] + wayuComponents + balineseComponents + additionalVoices) where item.state.phase == .downloading {
            await item.pause()
        }
    }
    func pauseAll() async {
        // Stop queue monitors before pausing tasks, otherwise they can resume a paused part.
        queueTask?.cancel(); voiceQueueTask?.cancel()
        await recognition.pause()
        await opus.pause()
        for package in opusDirections.packages { await package.pause() }
        #if os(macOS)
        await indexMLX.pause()
        #endif
        await pauseVoiceDownloads()
        queueTask?.cancel(); await queueTask?.value
        for downloader in downloaders where downloader.state.phase == .downloading { await downloader.pause() }
    }
    func cancelOpus() async {
        queueTask?.cancel(); await queueTask?.value
        await opus.cancel()
    }
    func cancel(_ downloader: ModelDownloader) async {
        #if os(macOS)
        if indexMLX.contains(downloader) { queueTask?.cancel(); await queueTask?.value; await indexMLX.cancel(); return }
        #endif
        if opus.contains(downloader) { await cancelOpus(); return }
        voiceQueueTask?.cancel(); await voiceQueueTask?.value
        queueTask?.cancel(); await queueTask?.value
        let id = packageOwner(downloader).model.id
        jobs[id]?.cancel(); await jobs[id]?.value
        for item in components(downloader) { await item.cancel() }
    }
    func remove(_ downloader: ModelDownloader) async {
        #if os(macOS)
        if indexMLX.contains(downloader) { await cancel(downloader); await indexMLX.remove(); return }
        #endif
        if opus.contains(downloader) { await cancelOpus(); await opus.remove(); return }
        if components(downloader).count > 1 {
            let owner = packageOwner(downloader)
            await cancel(owner)
            if let package = manifests[owner.model.id] {
                do { try await store.remove(package) }
                catch { errors[owner.model.id] = error.localizedDescription; return }
            }
            for part in components(downloader) { voiceDirectories[part.model.id] = nil }
            for item in components(downloader) {
                do { try await item.store.remove(item.model); await item.clearInstalledReference(); voiceDirectories[item.model.id] = nil }
                catch { errors[item.model.id] = error.localizedDescription }
            }
            return
        }
        await cancel(downloader)
        let id = downloader.model.id
        if let package = manifests[id] {
            do { try await store.remove(package); voiceDirectories[id] = nil }
            catch { errors[id] = error.localizedDescription; return }
        }
        // cancel resets phase, so deleting the stored file uses the store directly.
        do { try await downloader.store.remove(downloader.model) }
        catch { errors[id] = error.localizedDescription }
        await downloader.clearInstalledReference()
    }
}
