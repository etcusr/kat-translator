import XCTest
#if os(macOS)
import Carbon
import AppKit
#endif

final class OpusUITests: XCTestCase {
    @MainActor private func press(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }
    @MainActor func testRetiredModelsAreAbsent() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en"]
        app.launch(); defer { app.terminate() }
        let models = app.buttons["Models"].firstMatch
        XCTAssertTrue(models.waitForExistence(timeout: 120)); press(models)
        XCTAssertTrue(app.buttons["model.select.index-translate-9b-q4km"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["model.select.opus-mt-big-en-zle-int8"].exists)
        for id in ["translategemma-4b-q4km", "mil-mmt46-4b-v1-q4km", "mil-mmt46-12b-v1-q4km", "qwen35-9b-q4km"] {
            XCTAssertFalse(app.buttons["model.select." + id].exists)
            XCTAssertFalse(app.buttons["model.info." + id].exists)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Only Index and OPUS"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testOpusLanguagesAndInformation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en",
            "-selectedTranslationModel", "opus-mt-big-en-zle-int8", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO"]
        app.launch(); defer { app.terminate() }
        #if os(macOS)
        let textMode = app.buttons["mode.text"]
        #else
        let textMode = app.segmentedControls.buttons["Text"]
        #endif
        XCTAssertTrue(textMode.waitForExistence(timeout: 120)); press(textMode)
        XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 120)); press(app.buttons["language.target"])
        for id in ["en", "ru", "uk", "be"] { XCTAssertTrue(app.buttons["language.option." + id].waitForExistence(timeout: 10)) }
        XCTAssertFalse(app.buttons["language.option.de"].exists)
        press(app.buttons["language.close"])
        press(app.buttons["Models"].firstMatch)
        let info = app.buttons["model.info.opus-mt-big-en-zle-int8"]
        XCTAssertTrue(info.waitForExistence(timeout: 15)); press(info)
        XCTAssertTrue(app.staticTexts["Compact offline translator · smaller download and memory use"].waitForExistence(timeout: 10))
        let infoShot = XCTAttachment(screenshot: app.screenshot()); infoShot.name = "OPUS benefits"; infoShot.lifetime = .keepAlways; add(infoShot)
        press(app.buttons["model.languages.open"])
        let count = app.staticTexts["model.languages.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.value as? String ?? count.label, "Translation languages in the app: 4")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "OPUS four languages"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testRussianEnglishSetupRecommendsOpus() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
            "-appInterfaceLanguage", "en", "-languageSetup", "", "-translationSource", "ru", "-translationTarget", "en",
            "-selectedTranslationModel", "index-translate-9b-q4km"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Models"].firstMatch.waitForExistence(timeout: 120)); press(app.buttons["Models"].firstMatch)
        XCTAssertTrue(app.buttons["models.languageSetup"].waitForExistence(timeout: 15)); press(app.buttons["models.languageSetup"])
        let recommendation = app.descendants(matching: .any).matching(identifier: "setup.translation.model").firstMatch
        XCTAssertTrue(recommendation.waitForExistence(timeout: 15))
        XCTAssertEqual(recommendation.value as? String, "OPUS Big")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Russian English setup recommends OPUS"; shot.lifetime = .keepAlways; add(shot)
        let search = app.textFields["setup.search.targets"]
        press(search); search.typeText("Japanese")
        XCTAssertTrue(app.buttons["setup.target.ja"].waitForExistence(timeout: 10)); press(app.buttons["setup.target.ja"])
        XCTAssertEqual(recommendation.value as? String, "Index-Translate 9B")
    }
    @MainActor func testInstalledOpusTranslatesSixDirections() throws {
        continueAfterFailure = false
        #if os(macOS)
        let previousInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        _ = TISSelectInputSource(TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue())
        defer { _ = TISSelectInputSource(previousInput) }
        #endif
        let app = XCUIApplication()
        defer { app.terminate() }
        let english = "Please do not close the window. The train leaves at 18:45."
        let cases = [("en", "ru", english), ("en", "uk", english), ("en", "be", english),
                     ("ru", "en", "Пожалуйста, не закрывайте окно. Поезд отправляется в 18:45."),
                     ("uk", "en", "Будь ласка, не зачиняйте вікно. Потяг вирушає о 18:45."),
                     ("be", "en", "Калі ласка, не зачыняйце акно. Цягнік адпраўляецца а 18:45.")]
        #if os(macOS)
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer {
            if cases.contains(where: { $0.2 == board.string(forType: .string) }) {
                board.clearContents(); board.writeObjects(saved)
            }
        }
        #endif
        for (source, target, text) in cases {
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-languageSetupCompleted", "YES", "-automaticModelLoad", "YES",
                "-appInterfaceLanguage", "en", "-selectedTranslationModel", "opus-mt-big-en-zle-int8",
                "-translationSource", source, "-translationTarget", target, "-automaticLanguage", "NO",
                "-automaticSpeechText", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
            app.launch()
            #if os(macOS)
            let textMode = app.buttons["mode.text"]
            #else
            XCUIDevice.shared.orientation = .portrait
            let textMode = app.segmentedControls.buttons["Text"]
            #endif
            XCTAssertTrue(textMode.waitForExistence(timeout: 120)); press(textMode)
            let editor = app.textViews["Original text"]
            XCTAssertTrue(editor.waitForExistence(timeout: 60)); press(editor)
            #if os(macOS)
            board.clearContents(); board.setString(text, forType: .string)
            app.typeKey("v", modifierFlags: .command)
            #else
            editor.typeText(text)
            #endif
            XCTAssertEqual((editor.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), text)
            #if os(iOS)
            if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
            #endif
            let translate = app.buttons["text.translate"]
            XCTAssertTrue(translate.waitForExistence(timeout: 120))
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: translate)], timeout: 120) == .completed)
            press(translate)
            let output = app.staticTexts["text.translation.text"]
            let complete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                output.exists && (output.value as? String ?? output.label).contains("18:45") && app.buttons["text.copy.target"].isEnabled
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 120), .completed, app.debugDescription)
            let translatedText = output.value as? String ?? output.label
            XCTAssertNotEqual(translatedText, text)
            let result = XCTAttachment(string: "\(source) → \(target)\n\(text)\n\n\(translatedText)")
            result.name = "OPUS " + source + "-" + target; result.lifetime = .keepAlways; add(result)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = result.name; image.lifetime = .keepAlways; add(image)
            app.terminate()
        }
    }
}
