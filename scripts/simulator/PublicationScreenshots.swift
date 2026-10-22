import XCTest

/// Real UI capture in the dedicated simulator. No fabricated translation or downloads.
final class PublicationScreenshots: XCTestCase {
    @MainActor func testEnglish() throws { try captureLocale("en", textMode: "Text") }
    @MainActor func testRussian() throws { try captureLocale("ru", textMode: "Текст") }
    @MainActor func testSpanish() throws { try captureLocale("es", textMode: "Texto") }
    @MainActor func testTurkish() throws { try captureLocale("tr", textMode: "Metin") }

    @MainActor private func captureLocale(_ language: String, textMode: String) throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Publication fixture is restricted to the simulator")
        #else
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kattranslator")
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
            "-appInterfaceLanguage", language, "-selectedTranslationModel", "index-translate-2b-q4km",
            "-translationAuto", "NO", "-translationSource", "ru", "-translationTarget", "en",
            "-automaticSpeechVoice", "NO", "-showTechnicalInfo", "NO",
            "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 60))
        app.segmentedControls.firstMatch.buttons[textMode].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("Добрый день! Подскажите, пожалуйста, как пройти к вокзалу?")
        app.buttons["text.translate"].tap()
        let copy = app.buttons["text.copy.target"]
        XCTAssertTrue(copy.waitForExistence(timeout: 120))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy)
        wait(for: [ready], timeout: 120)
        shot(app, language, "01-text")
        app.buttons["language.target"].tap()
        XCTAssertTrue(app.buttons["language.close"].waitForExistence(timeout: 10))
        shot(app, language, "02-languages")
        app.buttons["language.close"].tap()
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.buttons["settings.category.models"].waitForExistence(timeout: 10))
        shot(app, language, "03-settings")
        app.buttons["settings.category.models"].tap()
        XCTAssertTrue(app.buttons["settings.category.voices"].waitForExistence(timeout: 10))
        shot(app, language, "04-models-and-voices")
        app.buttons["settings.category.voices"].tap()
        XCTAssertTrue(app.otherElements["voices.coverage"].exists || app.staticTexts["voices.coverage"].waitForExistence(timeout: 10))
        shot(app, language, "05-voices")
        app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch.tap()
        app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch.tap()
        app.buttons["settings.setup"].tap()
        XCTAssertTrue(app.switches["setup.recognition"].waitForExistence(timeout: 10))
        shot(app, language, "06-quick-setup")
        #endif
    }

    @MainActor private func shot(_ app: XCUIApplication, _ language: String, _ screen: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "publication-ios-\(language)-\(screen)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
