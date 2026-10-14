import XCTest
@testable import OfflineCore

final class TranslationPreflightTests: XCTestCase {
    func testFitsSourceButNotEstimatedResponse() {
        // Two news articles together are below the input cap but leave too little room for their translation.
        XCTAssertFalse(TranslationPreflight.fits(promptTokens: 1223, sourceTokens: 1193))
        // The original article remains one request, including its longer-than-512-token response.
        XCTAssertTrue(TranslationPreflight.fits(promptTokens: 683, sourceTokens: 653))
    }

    func testPromptOverheadConsumesContextButDoesNotExpandLikeSourceText() {
        XCTAssertTrue(TranslationPreflight.fits(promptTokens: 1400, sourceTokens: 100))
        XCTAssertFalse(TranslationPreflight.fits(promptTokens: 1400, sourceTokens: 500))
        XCTAssertFalse(TranslationPreflight.fits(promptTokens: 1537, sourceTokens: 10))
    }

    func testSafetyMarginAndFractionalTokenAtWindowBoundary() {
        // 30 prompt tokens + 780 source + 1170 estimated output + 64 reserve = 2044.
        XCTAssertTrue(TranslationPreflight.fits(promptTokens: 810, sourceTokens: 780))
        XCTAssertTrue(TranslationPreflight.fits(promptTokens: 811, sourceTokens: 781))
        XCTAssertFalse(TranslationPreflight.fits(promptTokens: 812, sourceTokens: 782))
    }

    func testInvalidCountsNeverPassPreflight() {
        for (prompt, source) in [(0, 0), (-1, 20), (20, -1), (20, 21), (Int.max, Int.max)] {
            XCTAssertFalse(TranslationPreflight.fits(promptTokens: prompt, sourceTokens: source))
        }
    }
}
