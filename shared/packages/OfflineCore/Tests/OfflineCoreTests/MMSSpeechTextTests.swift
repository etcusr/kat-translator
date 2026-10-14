import XCTest
@testable import OfflineCore
final class MMSSpeechTextTests: XCTestCase {
    func testRejectsForeignLettersInsteadOfDroppingThem() throws {
        let tokens = "  0\nh 1\ne 2\nl 3\no 4\n"
        XCTAssertEqual(try MMSSpeechText.prepare("Hello!", tokens: tokens, language: "la"), "hello!")
        XCTAssertThrowsError(try MMSSpeechText.prepare("Hello кот", tokens: tokens, language: "la"))
        XCTAssertThrowsError(try MMSSpeechText.prepare("12", tokens: tokens, language: "la"))
    }
    func testExpandsNumbersOnlyWithVerifiedLanguageFormatter() throws {
        let tokens = "  0\nб 1\nа 2\nр 3\nо 4\n" // Bengali below; exact output checked, not fallback English.
        _ = tokens
        let bengali = "ব 0\nা 1\nর 2\nো 3\n"
        XCTAssertEqual(try MMSSpeechText.prepare("12", tokens: bengali, language: "bn"), "বারো")
        XCTAssertThrowsError(try MMSSpeechText.prepare("12", tokens: bengali, language: "mn"))
    }
}
