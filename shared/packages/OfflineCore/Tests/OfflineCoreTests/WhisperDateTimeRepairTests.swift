import XCTest
@testable import OfflineCore

final class WhisperDateTimeRepairTests: XCTestCase {
    func testDefaultAndExplicitDateRepairPreferences() throws {
        let name = "WhisperDateTimeRepairTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(WhisperDateTimeRepair.isEnabled(in: defaults), WhisperDateTimeRepair.defaultEnabled)
        XCTAssertNil(defaults.object(forKey: "whisperDateTimeRepair"))
        defaults.set(false, forKey: "whisperDateTimeRepair")
        XCTAssertFalse(WhisperDateTimeRepair.isEnabled(in: defaults))
        defaults.set(true, forKey: "whisperDateTimeRepair")
        XCTAssertTrue(WhisperDateTimeRepair.isEnabled(in: defaults))
        defaults.removeObject(forKey: "whisperDateTimeRepair")
        XCTAssertEqual(WhisperDateTimeRepair.isEnabled(in: defaults), WhisperDateTimeRepair.defaultEnabled)
    }
    func testRepairIsDisabledByDefault() {
        XCTAssertFalse(WhisperDateTimeRepair.needsRetry("Поезд прибудет 22.18.16 октября.", language: .russian))
    }

    func testRequiresSpokenOrdinalEvidenceBeforeSeparatingTimeAndDate() {
        let original = "Поезд прибудет 22.18.16 октября."
        XCTAssertTrue(WhisperDateTimeRepair.needsRetry(original, language: .russian, enabled: true))
        XCTAssertEqual(WhisperDateTimeRepair.repair(original, retry: "Поезд прибудет. Двадцать два восемнадцать шестнадцатого октября."), "Поезд прибудет 22:18, 16 октября.")
        XCTAssertEqual(WhisperDateTimeRepair.repair(original, retry: "Поезд прибудет двадцать два восемнадцать шестнадцать октября."), original)
    }
    func testPreservesOtherWordsAndRejectsChangedNumbersOrHallucinations() {
        let original = "Поезд прибудет 22.18.16 октября."
        for retry in ["Поезд прибудет двадцать два девятнадцать шестнадцатого октября.",
                      "Самолёт прибудет двадцать два восемнадцать шестнадцатого октября.",
                      "Поезд прибудет двадцать два восемнадцать шестнадцатого ноября.",
                      "Поезд прибудет двадцать два восемнадцать шестнадцатого октября. Спасибо за просмотр.",
                      "Поезд прибудет двадцать два восемнадцать шестнадцатого октября." + String(repeating: " .", count: 30)] {
            XCTAssertEqual(WhisperDateTimeRepair.repair(original, retry: retry), original)
        }
    }
    func testDoesNotReinterpretOrdinaryNumbersDatesVersionsOrForeignText() {
        for text in ["Встреча 16.10.2026 в 22:18.", "Встреча 16 октября в 22:18.",
                     "Цена 22.18 рубля, скидка 16 процентов.", "Версия 22.18.16.",
                     "Телефон 79991234567.", "Код 22.18.16 октября — идентификатор.",
                     "Встреча 99.18.16 октября.", "Встреча 22.99.16 октября.",
                     "Встреча 22.18.31 апреля.", "Встреча 22.18.30 февраля.",
                     "Встреча 122.18.16 октября.", "Встреча 1.22.18.16 октября."] {
            XCTAssertFalse(WhisperDateTimeRepair.needsRetry(text, language: .russian, enabled: true), text)
        }
        XCTAssertFalse(WhisperDateTimeRepair.needsRetry("Поезд 22.18.16 октября.", language: .english, enabled: true))
    }
    func testZeroMinutesCompoundOrdinalAndCapitalization() {
        XCTAssertEqual(WhisperDateTimeRepair.repair("Встреча в 9.00.31 января!", retry: "Встреча в девять ноль тридцать первого января!"), "Встреча в 9:00, 31 января!")
        XCTAssertEqual(WhisperDateTimeRepair.repair("Приезжаю 0.05.4 МАЯ.", retry: "Приезжаю ноль пять четвёртого мая."), "Приезжаю 0:05, 4 МАЯ.")
    }
    func testDoesNotGuessDateFirstOrMultipleAmbiguities() {
        let text = "Поезд 16.18.10 октября."
        XCTAssertEqual(WhisperDateTimeRepair.repair(text, retry: "Поезд шестнадцатого в восемнадцать десять октября."), text)
        XCTAssertFalse(WhisperDateTimeRepair.needsRetry("Поезд 22.18.16 октября, автобус 23.10.17 октября.", language: .russian, enabled: true))
    }
    func testHyphenatedTripleAndSpokenLeadingZero() {
        XCTAssertEqual(WhisperDateTimeRepair.repair("Поезд прибудет 22-18-16 октября.", retry: "Поезд прибудет двадцать два восемнадцать шестнадцатого октября."), "Поезд прибудет 22:18, 16 октября.")
        XCTAssertEqual(WhisperDateTimeRepair.repair("Встречаемся в 9.05.31 января.", retry: "Встречаемся в девять ноль пять тридцать первого января."), "Встречаемся в 9:05, 31 января.")
    }
    func testUnrelatedNumbersAreNeverReplacedByRetry() {
        let original = "Номер 214, приезд 22.18.16 октября."
        XCTAssertEqual(WhisperDateTimeRepair.repair(original, retry: "Номер двести сорок один, приезд двадцать два восемнадцать шестнадцатого октября."), original)
        XCTAssertEqual(WhisperDateTimeRepair.repair("Два билета стоят 1250 рублей.", retry: "Два билета стоят тысячу рублей."), "Два билета стоят 1250 рублей.")
    }
}
