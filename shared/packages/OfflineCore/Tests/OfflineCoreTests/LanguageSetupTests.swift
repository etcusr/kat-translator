import XCTest
@testable import OfflineCore

final class LanguageSetupTests: XCTestCase {
    func testAutomaticPickerKeepsLanguagesOutsideTheCurrentlyLoadedOpusModel() {
        let ids = TranslationLanguage.selectable(for: .opusBig, automatic: true).map(\.id)
        XCTAssertTrue(ids.contains("ja")); XCTAssertTrue(ids.contains("de"))
        XCTAssertFalse(TranslationLanguage.selectable(for: .opusBig, automatic: false).map(\.id).contains("ja"))
    }
    func testInstalledGroupRouteWinsOverMissingSpecificRoute() throws {
        let data = Data("""
        [{"id":"specific","direction":"bg-en","sources":["bg"],"targets":["en"],"markers":{},"parts":[]},
         {"id":"group","direction":"zls-en","sources":["bg","hr"],"targets":["en"],"markers":{},"parts":[]}]
        """.utf8)
        let routes = try OpusDirectionRoutes.decode(data)
        XCTAssertEqual(OpusDirectionRoutes.route("bg", "en", in: routes, available: { $0.packageID == "group" })?.packageID, "group")
        XCTAssertNil(OpusDirectionRoutes.route("bg", "en", in: routes, available: { _ in false }))
    }
    func testEnglishRussianOnlyNeedsClassicWhisper() {
        let plan = LanguageSetup(primaryID: "ru", targetIDs: ["en"])
        XCTAssertEqual(plan.recognitionIDs, [ModelDescriptor.turbo.id])
        XCTAssertEqual(plan.voiceLanguages.map(\.rawValue).sorted(), ["en", "ru"])
        XCTAssertEqual(plan.recommendedTranslation, .opusBig)
    }
    func testMixedLanguagesAndTextOnly() {
        let plan = LanguageSetup(primaryID: "ru", targetIDs: ["en", "th", "ban", "en", "ru"])
        XCTAssertEqual(plan.recognitionIDs, [ModelDescriptor.turbo.id, LanguageSetup.omnilingualID])
        XCTAssertEqual(plan.languages.count, 4)
        let text = LanguageSetup(primaryID: "ru", targetIDs: ["en"], recognition: false, speech: false)
        XCTAssertTrue(text.recognitionIDs.isEmpty)
        XCTAssertTrue(text.voiceLanguages.isEmpty)
        XCTAssertEqual(text.recommendedTranslation, .opusBig)
    }
    func testRussianEnglishRecommendsOpusInBothDirections() {
        XCTAssertEqual(LanguageSetup(primaryID: "en", targetIDs: ["ru"]).recommendedTranslation, .opusBig)
        XCTAssertEqual(LanguageSetup(primaryID: "ru", targetIDs: ["en", "en", "ru"]).recommendedTranslation, .opusBig)
    }
    func testAdditionalLanguagesKeepABroadCoverageModel() {
        XCTAssertEqual(LanguageSetup(primaryID: "ru", targetIDs: ["en", "ja"]).recommendedTranslation, .index9B)
        XCTAssertEqual(LanguageSetup(primaryID: "ru", targetIDs: ["en", "uk"]).recommendedTranslation, .index9B)
        XCTAssertEqual(LanguageSetup(primaryID: "ru", targetIDs: ["en", "ban"]).recommendedTranslation, .index9B)
        XCTAssertNotEqual(LanguageSetup(primaryID: "ru", targetIDs: []).recommendedTranslation, .opusBig)
        XCTAssertEqual(LanguageSetup(primaryID: "ru", targetIDs: ["en"]).recommendedTranslation(strongDevice: true), .index9B)
        XCTAssertEqual(LanguageSetup(primaryID: "ru", targetIDs: ["en"]).recommendedTranslation(strongDevice: false), .opusBig)
        XCTAssertEqual(TranslationModel.restoredSelection(nil), .index9B)
        XCTAssertEqual(TranslationModel.restoredSelection(TranslationModel.qwen9B.rawValue), .index9B)
    }
    func testAdditionalWhisperLanguagesReuseTheSameDownload() {
        var plan = LanguageSetup(primaryID: "ru", targetIDs: ["en"])
        plan.targetIDs.append("th")
        XCTAssertEqual(plan.recognitionIDs, [ModelDescriptor.turbo.id])
        plan.targetIDs += ["ja", "th"]
        XCTAssertEqual(plan.recognitionIDs.count, 1)
        XCTAssertEqual(LanguageSetup(primaryID: "th", targetIDs: ["ja"]).recognitionIDs, [ModelDescriptor.turbo.id])
    }
    func testSharedAndInstalledFilesAreNotCountedTwice() {
        let files = [DownloadRequirement(id: "shared", bytes: 100, installed: false),
                     DownloadRequirement(id: "shared", bytes: 100, installed: false),
                     DownloadRequirement(id: "voice", bytes: 30, installed: true)]
        XCTAssertEqual(DownloadRequirement.missingBytes(files), 100)
    }
    func testUltraOnlyDoesNotPretendToRecognizeThai() throws {
        let ultra = URL(fileURLWithPath: "/models/" + RecognitionCatalog.ultraID)
        let files = PipelineFiles(asr: nil, translation: URL(fileURLWithPath: "/mt"), voices: [:], ultra: ultra, recognitionPreference: .ultra)
        XCTAssertEqual(try files.recognitionURL(for: .russian), ultra)
        XCTAssertEqual(try files.recognitionURL(for: nil), ultra)
        XCTAssertThrowsError(try files.recognitionURL(for: .thai))
    }
    func testAutoTranslationFollowsDeviceAndInstalledModels() {
        let all: Set<TranslationModel> = [.opusBig, .index2B, .index9B]
        func resolve(_ s: SpeechLanguage, _ t: SpeechLanguage, strong: Bool, installed: Set<TranslationModel>, direction: Bool = false) -> TranslationModel? {
            AutoTranslation.resolve(source: s, target: t, strongDevice: strong, installed: { installed.contains($0) }, directionInstalled: { _, _ in direction })
        }
        XCTAssertEqual(resolve(.russian, .english, strong: true, installed: all), .index9B)
        XCTAssertEqual(resolve(.russian, .english, strong: false, installed: all), .opusBig)
        XCTAssertEqual(resolve(.russian, .japanese, strong: false, installed: all), .index2B)
        XCTAssertEqual(resolve(.russian, .german, strong: false, installed: all, direction: true), .opusDirections)
        XCTAssertEqual(resolve(.russian, .japanese, strong: false, installed: [.index9B]), .index9B)
        XCTAssertNil(resolve(.russian, .japanese, strong: false, installed: []))
    }
}
