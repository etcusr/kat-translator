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

    func testAbbreviatedEndingsUseKnownNounGenderAndNumber() {
        let examples = [
            ("на 1-й улице", "на первой улице"),
            ("до 3-й остановки", "до третьей остановки"),
            ("к 2-ой станции", "к второй станции"),
            ("перед 3-й школой", "перед третьей школой"),
            ("80-е годы", "восьмидесятые годы"),
            ("3-е места", "третьи места"),
            ("2-е место", "второе место"),
            ("3-и места", "третьи места"),
            ("80-ые годы", "восьмидесятые годы")
        ]
        for (input, expected) in examples {
            XCTAssertEqual(RussianSpeechText.expandOrdinals(input), expected, input)
        }
    }

    func testShortMUsesGoverningPreposition() {
        let examples = [
            ("перед 1-м рейсом", "перед первым рейсом"),
            ("над 3-м этажом", "над третьим этажом"),
            ("с 2-м ребёнком", "с вторым ребёнком"),
            ("в 1-м классе", "в первом классе"),
            ("о 3-м месте", "о третьем месте"),
            ("Перед 21-м рейсом", "Перед двадцать первым рейсом")
        ]
        for (input, expected) in examples {
            XCTAssertEqual(RussianSpeechText.expandOrdinals(input), expected, input)
        }
    }

    func testUncertainAbbreviationsArePreserved() {
        for input in ["1-й", "с 1-й", "1-м", "80-е", "1-й авеню", "1-й новой улице",
                      "3-е неизвестные", "1-м способом", "1-й. улице", "на 1-м и 2-м", "3-е пришли"] {
            XCTAssertEqual(RussianSpeechText.expandOrdinals(input), input)
        }
    }

    func testDatesAndExplicitEndingsStillExpand() {
        let examples = [
            ("Перенесите с 15-го на 16-е октября.", "Перенесите с пятнадцатого на шестнадцатое октября."),
            ("31-е декабря", "тридцать первое декабря"),
            ("3-е число", "третье число"),
            ("3-им рейсом, 1-ом классе", "третьим рейсом, первом классе"),
            ("1-ая улица, 3-ю станцию", "первая улица, третью станцию"),
            ("2-ые места, 3-ие места", "вторые места, третьи места")
        ]
        for (input, expected) in examples {
            XCTAssertEqual(RussianSpeechText.expandOrdinals(input), expected, input)
        }
    }
}
