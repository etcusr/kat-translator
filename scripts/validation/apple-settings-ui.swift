import XCTest
#if os(macOS)
import AppKit
#endif

/// Add to an external UI-test runner targeting an already installed development app.
/// Activates Kat without changing launch defaults; never downloads, removes or selects a model.
final class SettingsNavigationUITests: XCTestCase {
    @MainActor func testCategoriesAndVoices() throws {
        #if os(macOS)
        let app = XCUIApplication(bundleIdentifier: "org.openoffline.translator.mac")
        #else
        let app = XCUIApplication(bundleIdentifier: "app.kattranslator")
        #endif
        continueAfterFailure = false
        app.activate()
        let close = element("settings.close", in: app)
        let done = element("sheet.done", in: app)
        if close.exists { click(close) }
        else if done.exists { click(done) }
        let open = element("settings.open", in: app)
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: open)
        wait(for: [ready], timeout: 60)
        click(open)
        assertPresent("settings.category.models", in: app)
        capture(app, "settings-root")
        tap("settings.setup", in: app)
        assertPresent("setup.recognition", in: app)
        #if os(macOS)
        tap("setup.close", in: app)
        #else
        tap("sheet.done", in: app)
        #endif
        assertPresent("settings.category.models", in: app)

        let categories = [
            ("recording", "settings.recordingMode"),
            ("interface", "settings.interfaceLanguage"),
            ("memory", "settings.automaticModelLoad"),
            ("history", "history.recordText"),
            ("experimental", "settings.recordingPreprocessing"),
            ("about", "settings.copyVersion")
        ]
        for (page, control) in categories {
            tap("settings.category." + page, in: app)
            assertPresent(control, in: app)
            back(in: app)
            assertPresent("settings.category.models", in: app)
        }
        #if os(macOS)
        tap("settings.category.shortcuts", in: app)
        capture(app, "settings-shortcuts")
        back(in: app)
        #endif
        tap("settings.category.models", in: app)
        capture(app, "settings-models")
        for (page, control) in [("translationModels", "model.select.auto"),
                                ("recognitionModels", "settings.recognition.automatic"),
                                ("downloads", "models.allowCellular")] {
            tap("settings.category." + page, in: app)
            assertPresent(control, in: app)
            capture(app, "settings-" + page)
            back(in: app)
            assertPresent("settings.category.voices", in: app)
        }
        tap("settings.category.ocr", in: app)
        #if os(iOS)
        assertPresent("settings.ocr.openSource", in: app)
        #else
        XCTAssertTrue(app.staticTexts["Apple Vision"].waitForExistence(timeout: 5))
        #endif
        back(in: app)
        tap("settings.category.voices", in: app)
        assertPresent("voices.coverage", in: app)
        #if os(macOS)
        let search = app.textFields["voices.search"]
        #else
        let search = app.searchFields.firstMatch
        #endif
        if !search.isHittable {
            #if os(iOS)
            app.swipeDown()
            #endif
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        click(search)
        #if os(macOS)
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
        defer {
            board.clearContents()
            let items = saved.map { pairs -> NSPasteboardItem in
                let item = NSPasteboardItem(); for (type, data) in pairs { item.setData(data, forType: type) }; return item
            }
            board.writeObjects(items)
        }
        board.clearContents(); board.setString("Russian", forType: .string)
        search.typeKey("v", modifierFlags: .command)
        #else
        search.typeText("Russian")
        #endif
        print("SETTINGS_SEARCH " + String(describing: search.value))
        tap("voices.language.ru", in: app)
        capture(app, "settings-russian-voices")
        back(in: app)
        assertPresent("voices.language.ru", in: app)
        #if os(macOS)
        tap("settings.close", in: app)
        #else
        let cancelSearch = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Отмена", "Cancel", "Close", "Закрыть"])).firstMatch
        if cancelSearch.exists { click(cancelSearch) }
        tap("sheet.done", in: app)
        #endif
        assertPresent("settings.open", in: app)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func assertPresent(_ id: String, in app: XCUIApplication) {
        XCTAssertTrue(element(id, in: app).waitForExistence(timeout: 10), "Missing " + id)
    }
    private func tap(_ id: String, in app: XCUIApplication) {
        let item = element(id, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Missing " + id)
        #if os(iOS)
        for _ in 0..<3 where !item.isHittable { app.swipeUp() }
        #endif
        XCTAssertTrue(item.isHittable, "Not visible " + id)
        #if os(iOS)
        if id == "settings.setup" || id.hasPrefix("settings.category.") || id.hasPrefix("voices.language.") {
            // Exercise the empty trailing portion, not just the title/icon.
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
            return
        }
        #endif
        click(item)
    }
    private func click(_ item: XCUIElement) {
        #if os(macOS)
        item.click()
        #else
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any).matching(identifier: "NotificationShortLookView").firstMatch
        if banner.exists { banner.swipeUp() }
        item.tap()
        #endif
    }
    private func back(in app: XCUIApplication) {
        #if os(macOS)
        let button = app.buttons.matching(NSPredicate(format: "label IN %@", ["Назад", "Back"])).firstMatch
        #else
        let button = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        #endif
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        click(button)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        #if os(macOS)
        // XCTest screenshots may fail when the app is on a secondary display.
        guard ProcessInfo.processInfo.environment["KAT_CAPTURE_SETTINGS"] == "1" else {
            print("SETTINGS_PAGE " + name + "\n" + app.debugDescription); return
        }
        #endif
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
