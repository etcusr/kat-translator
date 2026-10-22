import XCTest

/// Explicit opt-in through --model-check after seeding; no model downloads.
final class ModelSmokeTests: XCTestCase {
    @MainActor func testVoicePreparation() throws {
        #if targetEnvironment(simulator)
        let app = XCUIApplication(bundleIdentifier: "app.kattranslator")
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
            "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-2b-q4km",
            "-translationAuto", "NO", "-translationSource", "ru", "-translationTarget", "en"]
        app.launch()
        let prepare = app.buttons["voice.prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 90)); prepare.tap()
        let record = app.buttons["voice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 90))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: record)
        wait(for: [ready], timeout: 90)
        print("SIMULATOR_ASR_MT_READY")
        app.terminate()
        #else
        throw XCTSkip("Simulator only")
        #endif
    }
    @MainActor func testSeededTextTranslation() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only")
        #else
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kattranslator")
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
            "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-2b-q4km",
            "-translationAuto", "NO", "-translationSource", "ru", "-translationTarget", "en",
            "-automaticSpeechVoice", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 120))
        app.segmentedControls.firstMatch.buttons["Text"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.tap(); editor.typeText("Привет, мир!")
        let translate = app.buttons["text.translate"]
        translate.tap()
        let result = app.buttons["text.copy.target"]
        XCTAssertTrue(result.waitForExistence(timeout: 120))
        let translated = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: result)
        wait(for: [translated], timeout: 120)
        let english = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Hello")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 15), app.debugDescription)
        print("SIMULATOR_TRANSLATION " + english.label)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "seeded-model-translation"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["text.clear.source"].tap()
        app.segmentedControls.firstMatch.buttons["Voice"].tap()
        #endif
    }
}
