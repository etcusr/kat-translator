import XCTest
@testable import OfflineCore

final class L10nTests: XCTestCase {
    func testExplicitInterfaceLanguageOverridesSystem() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "appInterfaceLanguage")
        defer {
            if let previous { defaults.set(previous, forKey: "appInterfaceLanguage") }
            else { defaults.removeObject(forKey: "appInterfaceLanguage") }
        }
        defaults.set("ru", forKey: "appInterfaceLanguage")
        XCTAssertEqual(L10n.language, "ru")
        defaults.set("en", forKey: "appInterfaceLanguage")
        XCTAssertEqual(L10n.language, "en")
        for language in ["es", "tr"] {
            AppInterfaceLanguage.shared.preference = language
            XCTAssertEqual(AppInterfaceLanguage.shared.preference, language)
            XCTAssertEqual(L10n.language, language)
        }
        defaults.set("system", forKey: "appInterfaceLanguage")
        XCTAssertEqual(L10n.language, L10n.language(for: Locale.preferredLanguages))
        defaults.set("invalid", forKey: "appInterfaceLanguage")
        XCTAssertEqual(L10n.language, L10n.language(for: Locale.preferredLanguages))
    }
    func testSupportedLanguagesAndEnglishFallback() {
        XCTAssertEqual(L10n.language(for: ["ru-RU", "en-US"]), "ru")
        XCTAssertEqual(L10n.language(for: ["en_GB", "ru"]), "en")
        XCTAssertEqual(L10n.language(for: ["fr-FR", "ru"]), "ru")
        XCTAssertEqual(L10n.language(for: ["th-TH"]), "en")
        XCTAssertEqual(L10n.language(for: []), "en")
        XCTAssertEqual(L10n.language(for: ["es-ES", "en"]), "es")
        XCTAssertEqual(L10n.language(for: ["tr_TR", "ru"]), "tr")
        XCTAssertEqual(L10n.language(for: ["sr-Latn-ME"]), "en")
        XCTAssertEqual(L10n.language(for: ["fr", "es"]), "es")
    }

    func testInterpolationAndPercentLiterals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let en = root.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: en, withIntermediateDirectories: true)
        let strings = ["Часть %@ из %@": "%2$@ total, part %1$@", "Текст: %@": "Text: %@", "100%% готово": "100%% ready", "%%.2f с": "%%.2f s"]
        let data = try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
        try data.write(to: en.appendingPathComponent("Localizable.strings"))
        let bundle = try XCTUnwrap(Bundle(path: root.path))
        XCTAssertEqual(L10n.text("Часть \(2) из \(5)", bundle: bundle, language: "en"), "5 total, part 2")
        XCTAssertEqual(L10n.text("Текст: \("100% %@ русский")", bundle: bundle, language: "en"), "Text: 100% %@ русский")
        XCTAssertEqual(L10n.text("100% готово", bundle: bundle, language: "en"), "100% ready")
        XCTAssertEqual(L10n.text("%.2f с", bundle: bundle, language: "en"), "%.2f s")
    }
    func testBytesFollowAppLanguage() {
        XCTAssertEqual(L10n.bytes(5_240_000_000, language: "en"), "5.24\u{00A0}GB")
        XCTAssertEqual(L10n.bytes(5_240_000_000, language: "ru"), "5,24\u{00A0}ГБ")
        XCTAssertEqual(L10n.bytes(492_700_000, language: "ru"), "492,7\u{00A0}МБ")
        XCTAssertEqual(L10n.bytes(128_800_000, language: "en"), "128.8\u{00A0}MB")
        XCTAssertEqual(L10n.bytes(5_240_000_000, language: "es"), "5,24\u{00A0}GB")
        XCTAssertEqual(L10n.bytes(5_240_000_000, language: "tr"), "5,24\u{00A0}GB")
        XCTAssertEqual(L10n.bytes(0, language: "ru"), "0\u{00A0}байт")
    }
}
