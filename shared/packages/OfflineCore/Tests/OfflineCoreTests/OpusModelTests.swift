import XCTest
@testable import OfflineCore

final class OpusModelTests: XCTestCase {
    func testFourLanguagesAndSixDirectDirections() throws {
        XCTAssertEqual(Set(TranslationLanguage.supported(by: .opusBig).map(\.id)), ["en", "ru", "uk", "be"])
        for id in ["ru", "uk", "be"] {
            let language = try XCTUnwrap(SpeechLanguage(rawValue: id))
            XCTAssertTrue(TranslationModel.opusBig.supports(source: .english, target: language))
            XCTAssertTrue(TranslationModel.opusBig.supports(source: language, target: .english))
        }
        XCTAssertFalse(TranslationModel.opusBig.supports(source: .russian, target: try XCTUnwrap(SpeechLanguage(rawValue: "uk"))))
        XCTAssertFalse(TranslationModel.opusBig.supports(source: .english, target: .chinese))
        XCTAssertFalse(LanguageSelection(sourceID: "ru", targetID: "be").connected(to: .opusBig))
    }
    func testSelectionRestoresWithoutChangingDefault() {
        XCTAssertEqual(TranslationModel.restoredSelection(TranslationModel.opusBig.rawValue), .opusBig)
        XCTAssertEqual(TranslationModel.restoredSelection(nil), .index9B)
        XCTAssertTrue(TranslationModel.selectable.contains(.opusBig))
        XCTAssertFalse(TranslationModel.opusBig.requiresGemmaTerms)
    }
    func testSentenceAndBudgetSplittingPreservesAllSourceText() throws {
        let text = "First sentence. Second sentence!\n\nНова сторінка. Інше речення.\n\nБеларускі тэкст. Яшчэ сказ."
        let parts = try OpusTextSegments.split(text) { $0.count <= 20 }
        XCTAssertEqual(parts.joined(), text)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 20 })
        XCTAssertTrue(parts.contains { $0.hasPrefix("\n\n") })
    }
    func testLargeUnbrokenTextIsNeverTruncated() throws {
        let text = String(repeating: "世界", count: 1_000)
        let parts = try OpusTextSegments.split(text) { $0.count <= 100 }
        XCTAssertEqual(parts.joined(), text)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 100 })
    }
}
