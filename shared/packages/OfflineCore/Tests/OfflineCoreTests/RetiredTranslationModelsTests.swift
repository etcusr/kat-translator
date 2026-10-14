import XCTest
@testable import OfflineCore

final class RetiredTranslationModelsTests: XCTestCase {
    func testRemovalPreservesOtherModelsVoicesHistoryAndASR() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let removed = RetiredTranslationModels.ids.flatMap {
            ["Models/\($0).bin", "Models/\($0).json", "Models/\($0).verified.json",
             "Downloads/\($0)/resume.data", "Downloads/\($0)/staging-1.bin"]
        } + RetiredTranslationModels.developmentFilenames.map { "Documents/DevelopmentModels/" + $0 }
        let retained = ["Models/index-translate-9b-q4km.bin", "Models/whisper-large-v3-turbo-f16.bin",
                        "Translationshared/packages/opus-mt-big-en-zle-int8/en-zle/model.bin", "Voiceshared/packages/ru/model.onnx",
                        "History/history.json", "Models/qwen35-9b-q4km-unrelated.bin",
                        "Documents/DevelopmentModels/qwen3-asr-06b/model.safetensors"]
        for path in removed + retained {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
        try RetiredTranslationModels.removeFiles(root: root, documents: root.appendingPathComponent("Documents"))
        try RetiredTranslationModels.removeFiles(root: root, documents: root.appendingPathComponent("Documents"))
        for path in removed { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), path) }
        for path in retained { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(path.utf8)) }
    }

    func testRetiredSelectionFallsBackAndOldHistoryIDsStillDecode() throws {
        XCTAssertEqual(TranslationModel.selectable, [.opusBig, .opusDirections, .index2B, .index9B])
        for id in RetiredTranslationModels.ids {
            XCTAssertEqual(TranslationModel.restoredSelection(id), .index9B)
            XCTAssertEqual(try JSONDecoder().decode(TranslationModel.self, from: JSONEncoder().encode(id)).rawValue, id)
        }
        XCTAssertEqual(TranslationModel.restoredSelection(TranslationModel.opusBig.rawValue), .opusBig)
    }

    func testPreferenceMigrationIsScoped() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(TranslationModel.qwen9B.rawValue, forKey: "selectedTranslationModel")
        defaults.set("zh-Hant", forKey: "translationSource")
        defaults.set("ru", forKey: "translationTarget")
        defaults.set("zh-Hant", forKey: "quickTranslationTarget")
        defaults.set("unchanged", forKey: "history")
        defaults.set(true, forKey: "downloadAllPending")
        defaults.set(try JSONEncoder().encode(LanguageSetup(primaryID: "ru", targetIDs: ["zh", "zh-Hant", "en"])), forKey: "languageSetup")
        RetiredTranslationModels.migratePreferences(defaults)
        RetiredTranslationModels.migratePreferences(defaults)
        XCTAssertEqual(defaults.string(forKey: "selectedTranslationModel"), TranslationModel.index9B.rawValue)
        XCTAssertEqual(defaults.string(forKey: "translationSource"), "zh")
        XCTAssertEqual(defaults.string(forKey: "translationTarget"), "ru")
        XCTAssertEqual(defaults.string(forKey: "quickTranslationTarget"), "zh")
        XCTAssertEqual(defaults.string(forKey: "history"), "unchanged")
        XCTAssertFalse(defaults.bool(forKey: "downloadAllPending"))
        XCTAssertEqual(try JSONDecoder().decode(LanguageSetup.self, from: XCTUnwrap(defaults.data(forKey: "languageSetup"))).targetIDs, ["zh", "en"])
        defaults.set(TranslationModel.opusBig.rawValue, forKey: "selectedTranslationModel")
        RetiredTranslationModels.migratePreferences(defaults)
        XCTAssertEqual(defaults.string(forKey: "selectedTranslationModel"), TranslationModel.opusBig.rawValue)
    }

    func testOnlyBalineseIsOutsideIndexAndTraditionalChineseIsUnavailable() {
        XCTAssertFalse(TranslationLanguage.details(.lang_zh_Hant).available)
        for model in TranslationModel.selectable {
            XCTAssertFalse(TranslationLanguage.supported(by: model).contains { $0.id == "zh-Hant" })
        }
        XCTAssertEqual(TranslationLanguage.catalog.filter { $0.available && !$0.connected(to: .index9B) }.map(\.id), ["ban"])
        XCTAssertTrue(TranslationLanguage.details(.chinese).connected(to: .index9B))
        XCTAssertFalse(LanguageSetup(primaryID: "ru", targetIDs: ["ban"]).isValid)
        XCTAssertEqual(LanguageSelection(sourceID: "zh-Hant", targetID: "en").sourceID, "zh")
    }
}
