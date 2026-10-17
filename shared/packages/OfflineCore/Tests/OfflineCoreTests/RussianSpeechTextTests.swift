import XCTest
@testable import OfflineCore

final class RussianSpeechTextTests: XCTestCase {
    func testHyphenatedOrdinalsAreSpelledOut() {
        XCTAssertEqual(RussianSpeechText.expandOrdinals("Измените дату приезда с 15-го на 16-е октября."),
                       "Измените дату приезда с пятнадцатого на шестнадцатое октября.")
        XCTAssertEqual(RussianSpeechText.expandOrdinals("Я имел в виду 17-е, а не 16-е."), "Я имел в виду семнадцатое, а не шестнадцатое.")
        XCTAssertEqual(RussianSpeechText.expandOrdinals("в 2026-м году"), "в две тысячи двадцать шестом году")
        XCTAssertEqual(RussianSpeechText.expandOrdinals("3-я линия, 2-й этаж, 40-го размера"), "третья линия, второй этаж, сорокового размера")
        XCTAssertEqual(RussianSpeechText.expandOrdinals("к 21-му числу"), "к двадцать первому числу")
        XCTAssertEqual(RussianSpeechText.expandOrdinals("в 1990-х"), "в тысяча девятьсот девяностых")
        XCTAssertEqual(RussianSpeechText.expandOrdinals("100-й раз"), "сотый раз")
    }
    func testOtherTextIsUntouched() {
        for text in ["Цена 120 евро.", "Звоните 8-800-555-35-35", "Рейс SU-1234", "2,5-й", "16 октября", "2000-й год"] {
            XCTAssertEqual(RussianSpeechText.expandOrdinals(text), text)
        }
    }
}
