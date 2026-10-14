import XCTest
@testable import OfflineCore

final class TextLanguageDetectionTests: XCTestCase {
    func testShortEnglishGreetingFromPhone() {
        for text in ["Hello", "hello", "Hello!", "HELLO", "  Hello...  ", "Good morning"] {
            XCTAssertEqual(TextLanguageDetection.detect(text), .english, text)
        }
        for text in ["gift", "chat", "no", "OK"] {
            XCTAssertNil(TextLanguageDetection.detect(text), "Ambiguous word must not be forced to English: " + text)
        }
        XCTAssertEqual(TextLanguageDetection.detect("Привет"), .russian)
        XCTAssertEqual(TextLanguageDetection.detect("Bonjour"), .french)
        XCTAssertEqual(TextLanguageDetection.detect("Hola"), .spanish)
    }
    func testDetectsLanguagesBeyondRussianAndEnglish() {
        let examples: [(String, SpeechLanguage)] = [
            ("Доброго ранку! Підкажіть, будь ласка, де знаходиться найближча залізнична станція? Я хочу придбати квиток до Києва.", .lang_uk),
            ("Bonjour, pourriez-vous me dire où se trouve la gare la plus proche ? Je voudrais acheter un billet pour demain.", .french),
            ("Merhaba, en yakın tren istasyonunun nerede olduğunu söyleyebilir misiniz? Yarın için bir bilet almak istiyorum.", .turkish),
            ("God morgen! Kan du fortelle meg hvor nærmeste togstasjon ligger? Jeg vil gjerne kjøpe en billett til Oslo.", .lang_no),
            ("请告诉我最近的火车站在哪里。我想买一张明天去北京的车票。", .chinese),
            ("請告訴我最近的火車站在哪裡。我想買一張明天去臺北的車票。", .chinese)
        ]
        for (text, expected) in examples { XCTAssertEqual(TextLanguageDetection.detect(text), expected, text) }
    }
    func testBelarusianOrthographyIsNotMisidentifiedAsKazakh() {
        XCTAssertEqual(TextLanguageDetection.detect("Добрай раніцы! Падкажыце, калі ласка, дзе знаходзіцца найбліжэйшы чыгуначны вакзал? Я хачу набыць квіток да Мінска."), .lang_be)
        XCTAssertEqual(TextLanguageDetection.detect("Қазақстанның астанасы — Астана. Қазақ тілі — Қазақстан Республикасының мемлекеттік тілі."), .lang_kk)
    }
    func testEmptyAndNonLinguisticInputNeedsManualLanguage() {
        for text in ["", "  \n ", "12345 67890", "😀🎉", "--- …"] {
            XCTAssertNil(TextLanguageDetection.detect(text), text)
        }
    }
}
