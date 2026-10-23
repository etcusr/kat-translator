import XCTest

/// Presentation state only, in the isolated simulator build made by prepare.py.
/// This does not validate ASR, translation, playback or camera capture.
final class PublicationScreenshots: XCTestCase {
    @MainActor func testEnglish() throws { try capture("en") }
    @MainActor func testRussian() throws { try capture("ru") }
    @MainActor func testSpanish() throws { try capture("es") }
    @MainActor func testTurkish() throws { try capture("tr") }
    @MainActor private func capture(_ language: String) throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Presentation fixture is simulator-only")
        #else
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kattranslator")
        app.launchEnvironment["KAT_PUBLICATION_FIXTURE"] = "1"
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
            "-appInterfaceLanguage", language, "-selectedTranslationModel", "index-translate-2b-q4km",
            "-automaticLanguage", "NO", "-translationSource", "en", "-translationTarget", "ru",
            "-automaticSpeechVoice", "NO", "-showTechnicalInfo", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["voice.translation.text"].waitForExistence(timeout: 60))
        if !app.staticTexts["voice.original.text"].exists { app.buttons["voice.original.disclosure"].tap() }
        XCTAssertTrue(app.staticTexts["voice.original.text"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["voice.translation.text"].label, "Добрый день! Я хотел бы забронировать номер на двоих. Завтрак включён?")
        shot(app, language, "07-voice")
        app.segmentedControls.firstMatch.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["camera.close"].waitForExistence(timeout: 10))
        shot(app, language, "08-image")
        #endif
    }
    @MainActor private func shot(_ app: XCUIApplication, _ language: String, _ screen: String) {
        let item = XCTAttachment(screenshot: app.screenshot())
        item.name = "publication-ios-\(language)-\(screen)"; item.lifetime = .keepAlways; add(item)
    }
}
