import XCTest
@testable import OfflineCore

final class LanguageSelectionTests: XCTestCase {
    func testCompactLanguageCodesCoverCatalogAndPreserveScriptVariants() {
        XCTAssertEqual(TranslationLanguage.shortCode("en"), "eng")
        XCTAssertEqual(TranslationLanguage.shortCode("ru"), "rus")
        XCTAssertEqual(TranslationLanguage.shortCode("de"), "deu")
        XCTAssertEqual(TranslationLanguage.shortCode("ban"), "ban")
        XCTAssertEqual(TranslationLanguage.shortCode("sr-Latn"), "srp-latn")
        for language in TranslationLanguage.catalog {
            let base = TranslationLanguage.shortCode(language.id).split(separator: "-")[0]
            XCTAssertEqual(base.count, 3, language.id)
        }
    }
    func testSpeechExpansionKeepsTranslationCoverageIndependent() {
        for id in ["id", "vi", "uk", "pl", "hr", "ban"] {
            XCTAssertTrue(SpeechLanguage(rawValue: id)!.hasVoice, id)
        }
        XCTAssertFalse(SpeechLanguage(rawValue: "nrm")!.hasVoice)
        XCTAssertEqual(TranslationLanguage.catalog.filter { $0.connected(to: .gemma4B) }.count, 14)
    }
    func testSearchAndModelCapabilities() throws {
        let indonesian = TranslationLanguage.details(try XCTUnwrap(SpeechLanguage(rawValue: "id")))
        XCTAssertTrue(indonesian.matches("  ИНДОНЕЗ  "))
        XCTAssertTrue(indonesian.matches("Indonesian"))
        XCTAssertTrue(indonesian.matches("Indonesia"))
        XCTAssertFalse(indonesian.matches("несуществующий"))
        XCTAssertTrue(indonesian.connected(to: .index9B))
        XCTAssertTrue(indonesian.connected(to: .mil4B))
        XCTAssertFalse(indonesian.connected(to: .gemma4B))
        let balinese = TranslationLanguage.details(try XCTUnwrap(SpeechLanguage(rawValue: "ban")))
        XCTAssertTrue(balinese.connected(to: .qwen9B))
        XCTAssertFalse(balinese.connected(to: .index9B))
        XCTAssertNil(balinese.whisperCode)
        XCTAssertTrue(balinese.hasVoice)
        XCTAssertEqual(TranslationLanguage.catalog.filter { $0.connected(to: .index9B) }.count, 150)
        XCTAssertEqual(TranslationLanguage.catalog.filter { $0.connected(to: .mil4B) }.count, 45)
        XCTAssertEqual(SpeechLanguage(rawValue: "jv")?.whisperCode, "jw")
        XCTAssertNil(SpeechLanguage(rawValue: "sr-Latn")?.whisperCode)
        XCTAssertFalse(LanguageSelection(sourceID: "ru", targetID: "ban").connected(to: .index9B))
        XCTAssertTrue(LanguageSelection(sourceID: "ru", targetID: "ban").connected(to: .qwen9B))
        let request = TranslationModel.mil4B.request(text: "你好", source: .chinese, target: try XCTUnwrap(SpeechLanguage(rawValue: "tl")))
        XCTAssertEqual(request.text, "Translate this from Chinese (Simplified) to Tagalog:\nChinese (Simplified): 你好\nTagalog:")
    }
    func testExpandedCatalogKeepsCodesAndDoesNotInventVoices() throws {
        XCTAssertGreaterThanOrEqual(TranslationLanguage.catalog.count, 150)
        XCTAssertEqual(Set(TranslationLanguage.catalog.map(\.id)).count, TranslationLanguage.catalog.count)
        let indonesian = try XCTUnwrap(SpeechLanguage(rawValue: "id"))
        XCTAssertEqual(indonesian.englishName, "Indonesian")
        XCTAssertTrue(indonesian.hasVoice)
        XCTAssertTrue(LanguageSelection(sourceID: "ru", targetID: "id").isAvailable)
        XCTAssertNotNil(SpeechLanguage(rawValue: "ban"))
        XCTAssertTrue(SpeechLanguage.russian.hasVoice)
        XCTAssertEqual(String(data: try JSONEncoder().encode(SpeechLanguage.russian), encoding: .utf8), "\"ru\"")
    }
    func testPickingSameLanguageSwapsOtherSide() {
        var pair = LanguageSelection(sourceID: "ru", targetID: "en", automaticRequested: true)
        pair.selectSource("en")
        XCTAssertEqual(pair.sourceID, "en"); XCTAssertEqual(pair.targetID, "ru")
        pair.selectTarget("en")
        XCTAssertEqual(pair.sourceID, "ru"); XCTAssertEqual(pair.targetID, "en")
        pair.reverse()
        XCTAssertEqual(pair.sourceID, "en"); XCTAssertEqual(pair.targetID, "ru")
        XCTAssertFalse(pair.automaticRequested, "Choosing a source explicitly leaves automatic mode")
    }
    func testAutomaticSupportsAnyValidPairInEveryMode() {
        let pair = LanguageSelection(sourceID: "ru", targetID: "en", automaticRequested: true)
        XCTAssertTrue(pair.automaticActive(in: .voice))
        XCTAssertTrue(pair.automaticActive(in: .text)); XCTAssertTrue(pair.automaticActive(in: .camera))
        XCTAssertTrue(LanguageSelection(sourceID: "ru", targetID: "fr", automaticRequested: true).automaticActive(in: .voice))
        XCTAssertTrue(LanguageSelection(sourceID: "fr", targetID: "en", automaticRequested: true).automaticActive(in: .voice))
    }
    func testNewPairsResolveBothDirectionsWithAutomatic() {
        var pair = LanguageSelection(sourceID: "ja", targetID: "fr", automaticRequested: true)
        XCTAssertEqual(pair.runtimeSource, .japanese)
        XCTAssertEqual(pair.runtimeTarget, .french)
        XCTAssertTrue(pair.automaticActive(in: .voice))
        pair.reverse()
        XCTAssertEqual(pair.runtimeSource, .french)
        XCTAssertEqual(pair.runtimeTarget, .japanese)
        XCTAssertTrue(TranslationPrompt.prefix(source: .japanese, target: .french).contains("Japanese (ja) to French (fr)"))
    }
    func testUnsupportedPairCannotResolveToRuntimeLanguages() {
        let future = LanguageSelection(sourceID: "ru", targetID: "xx", automaticRequested: true)
        XCTAssertNil(future.runtimeSource)
        XCTAssertFalse(future.isAvailable)
        XCTAssertTrue(LanguageSelection(sourceID: "ru", targetID: "ru").isAvailable, "A manual source matching the quick target must remain explicit")
        XCTAssertEqual(LanguageSelection(sourceID: "en", targetID: "ru").runtimeSource, .english)
        XCTAssertTrue(TranslationLanguage.catalog.first(where: { $0.id == "fr" })!.available)
    }
}
