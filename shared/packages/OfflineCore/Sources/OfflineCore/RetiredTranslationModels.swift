import Foundation

/// Retired IDs remain decodable in history; only their model files are removed.
public enum RetiredTranslationModels {
    public static let ids = [TranslationModel.gemma4B, .mil4B, .mil12B, .qwen9B].map(\.rawValue)
    public static let developmentFilenames = [
        "translategemma-4b-it.Q4_K_M.gguf", "MiLMMT-46-4B-v1.0.Q4_K_M.gguf",
        "MiLMMT-46-12B-v1.0.Q4_K_M.gguf", "Qwen3.5-9B-Q4_K_M.gguf"
    ]

    public static func removeFiles(root: URL, documents: URL) throws {
        let paths = ids.flatMap { id in
            ["Models/\(id).bin", "Models/\(id).json", "Models/\(id).verified.json", "Downloads/\(id)"]
        }
        let urls = paths.map { root.appendingPathComponent($0) } + developmentFilenames.map {
            documents.appendingPathComponent("DevelopmentModels/" + $0)
        }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func migratePreferences(_ defaults: UserDefaults) {
        if let old = defaults.string(forKey: "selectedTranslationModel"), ids.contains(old) {
            defaults.set(TranslationModel.index9B.rawValue, forKey: "selectedTranslationModel")
            defaults.set(false, forKey: "downloadAllPending")
        }
        // The traditional-script entry is retired, not ordinary Chinese.
        for key in ["translationSource", "translationTarget", "quickTranslationTarget"] {
            if defaults.string(forKey: key) == "zh-Hant" { defaults.set("zh", forKey: key) }
        }
        if let data = defaults.data(forKey: "languageSetup"),
           var setup = try? JSONDecoder().decode(LanguageSetup.self, from: data),
           setup.primaryID == "zh-Hant" || setup.targetIDs.contains("zh-Hant") {
            if setup.primaryID == "zh-Hant" { setup.primaryID = "zh" }
            setup.targetIDs = setup.targetIDs.map { $0 == "zh-Hant" ? "zh" : $0 }
            var seen = Set([setup.primaryID])
            setup.targetIDs = setup.targetIDs.filter { seen.insert($0).inserted }
            if let updated = try? JSONEncoder().encode(setup) { defaults.set(updated, forKey: "languageSetup") }
        }
    }
}
