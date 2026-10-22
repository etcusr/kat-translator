import XCTest

/// Navigation only: no model downloads, recording or inference benchmarks.
final class SimulatorNavigationTests: XCTestCase {
    @MainActor func testMainModesAndLanguageMenus() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This fixture is restricted to the dedicated iOS Simulator")
        #else
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kattranslator")
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
                               "-appInterfaceLanguage", "en", "-showTechnicalInfo", "NO"]
        app.launch()
        let settings = app.buttons["settings.open"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        let modes = app.segmentedControls.firstMatch
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        modes.buttons["Text"].tap()
        XCTAssertTrue(app.buttons["text.translate"].waitForExistence(timeout: 10))

        for id in ["language.source", "language.target"] {
            app.buttons[id].tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap(); search.typeText("German")
            XCTAssertTrue(app.buttons["language.option.de"].waitForExistence(timeout: 10))
            let closeSearch = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch
            if closeSearch.exists { closeSearch.tap() }
            app.buttons["language.close"].tap()
        }

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("Hello from Kat Simulator.")
        // Tapping a mode also dismisses the software keyboard.
        modes.buttons["Voice"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        modes.buttons["Text"].tap()
        XCTAssertEqual(editor.value as? String, "Hello from Kat Simulator.")
        attach(app, "text-mode")

        app.buttons["toolbar.history"].tap()
        XCTAssertTrue(app.buttons["sheet.done"].waitForExistence(timeout: 10))
        attach(app, "history-empty")
        app.buttons["sheet.done"].tap()

        modes.buttons["Camera"].tap()
        let closeCamera = app.buttons["camera.close"]
        XCTAssertTrue(closeCamera.waitForExistence(timeout: 15))
        attach(app, "camera-simulator")
        closeCamera.tap()
        XCTAssertTrue(app.buttons["text.translate"].waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Hello from Kat Simulator.")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["text.translate"].waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Hello from Kat Simulator.")
        app.buttons["text.clear.source"].tap()
        modes.buttons["Voice"].tap()
        attach(app, "voice-mode")
        #endif
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
