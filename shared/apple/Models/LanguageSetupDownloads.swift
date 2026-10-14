import Foundation
import OfflineCore

extension PackageDownloadCoordinator {
    var languageSetup: LanguageSetup {
        guard let data = UserDefaults.standard.data(forKey: "languageSetup"),
              let value = try? JSONDecoder().decode(LanguageSetup.self, from: data), value.isValid else {
            return LanguageSetup(primaryID: UserDefaults.standard.string(forKey: "translationSource") ?? "ru",
                                 targetIDs: [UserDefaults.standard.string(forKey: "translationTarget") ?? "en"])
        }
        return value
    }
    func saveLanguageSetup(_ value: LanguageSetup) {
        guard value.isValid, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: "languageSetup")
        objectWillChange.send()
    }
    func setupVoices(_ setup: LanguageSetup) -> [ModelDownloader] {
        var seen = Set<String>()
        return setup.voiceLanguages.map { selectedVoice($0) }.filter { seen.insert($0.model.id).inserted }
    }
    /// Auto assembles translation per pair; an explicit choice downloads that one model.
    func setupTranslationFiles(_ setup: LanguageSetup, model: TranslationModel) -> [ModelDownloader] {
        guard autoTranslation else { return translationURL(for: model) != nil ? [] : translationFiles(model) }
        let plan = autoPlan(setup)
        return plan.models.flatMap { translationURL(for: $0) != nil ? [] : translationFiles($0) }
            + plan.directions.filter { $0.directory == nil }.flatMap(\.downloaders)
    }
    func setupTranslationReady(_ setup: LanguageSetup, model: TranslationModel) -> Bool {
        guard autoTranslation else { return translationURL(for: model) != nil }
        let plan = autoPlan(setup)
        return plan.models.allSatisfy { translationURL(for: $0) != nil } && plan.directions.allSatisfy { $0.directory != nil }
    }
    func setupFiles(_ setup: LanguageSetup, model: TranslationModel) -> [ModelDownloader] {
        var result = setupTranslationFiles(setup, model: model)
        if setup.recognitionIDs.contains(ModelDescriptor.turbo.id) { result += [whisper] }
        if setup.recognitionIDs.contains(LanguageSetup.omnilingualID) { result += [omnilingual] }
        result += setup.voiceLanguages.flatMap { components(selectedVoice($0)) }
        var seen = Set<String>()
        return result.filter { seen.insert($0.model.id).inserted }
    }
    func setupDownloadFiles(_ setup: LanguageSetup, model: TranslationModel) -> [ModelDownloader] {
        setupFiles(setup, model: model) + RecognitionPackages.definitions
            .filter { setup.recognitionIDs.contains($0.id) && recognition.directories[$0.id] == nil }
            .flatMap { recognition.parts($0) }
    }
    func setupRequirements(_ setup: LanguageSetup, model: TranslationModel) -> [DownloadRequirement] {
        var files = setupFiles(setup, model: model).map {
            DownloadRequirement(id: $0.model.id, bytes: $0.model.byteCount,
                                installed: $0.installedURL != nil || voiceDirectories[$0.model.id] != nil)
        }
        for definition in RecognitionPackages.definitions where setup.recognitionIDs.contains(definition.id) {
            files += recognition.parts(definition).map {
                DownloadRequirement(id: $0.model.id, bytes: $0.model.byteCount,
                    installed: recognition.directories[definition.id] != nil || $0.installedURL != nil)
            }
        }
        return files
    }
    func setupBytes(_ setup: LanguageSetup, model: TranslationModel) -> Int64 {
        DownloadRequirement.missingBytes(setupRequirements(setup, model: model))
    }
    func setupProgress(_ setup: LanguageSetup, model: TranslationModel) -> DownloadProgress {
        let files = Dictionary(downloaders.map { ($0.model.id, $0) }, uniquingKeysWith: { first, _ in first })
        return DownloadProgress(setupRequirements(setup, model: model).compactMap { requirement in
            guard let item = files[requirement.id] else { return nil }
            return .init(id: item.model.id, expected: item.model.byteCount,
                         received: item.state.receivedBytes, phase: item.state.phase,
                         ready: downloadReady(item), packageFailed: downloadPackageFailed(item))
        })
    }
    func setupReady(_ setup: LanguageSetup, model: TranslationModel) -> Bool {
        guard setupTranslationReady(setup, model: model) else { return false }
        for id in setup.recognitionIDs {
            if id == LanguageSetup.omnilingualID { if omnilingualDirectory == nil { return false } }
            else if id == ModelDescriptor.turbo.id { if whisper.installedURL == nil { return false } }
            else if recognition.directories[id] == nil { return false }
        }
        return setup.voiceLanguages.allSatisfy { canSpeak($0) }
    }
    /// Include the active pair when the user later selects a language outside the initial scope.
    var activeDownloadSetup: LanguageSetup {
        var setup = languageSetup
        setup.targetIDs += [UserDefaults.standard.string(forKey: "translationSource"), UserDefaults.standard.string(forKey: "translationTarget")].compactMap { $0 }
        return setup
    }
}
