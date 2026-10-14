import XCTest

final class TranslatorUITests: XCTestCase {
    /// Opt-in capture of real iPhone UI. The caller backs up and verifies the device
    /// preferences/history. Disable text history through its typed UI setting and restore it.
    @MainActor func testStoreScreenshotsRussian() throws {
        guard ProcessInfo.processInfo.environment["KAT_IOS_STORE_SHOTS"] == "1" else {
            throw XCTSkip("Opt-in App Store screenshots")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-appInterfaceLanguage", "ru",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-automaticModelLoad", "NO",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "ru", "-translationTarget", "en",
            "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-automaticSpeechVoice", "NO",
            "-showTechnicalInfo", "NO", "-memorySaving", "NO"]
        app.launch()
        func textHistory(_ enabled: Bool?) -> Bool {
            XCTAssertTrue(app.buttons["Настройки"].waitForExistence(timeout: 90))
            app.buttons["Настройки"].tap()
            let control = app.switches["history.recordText"]
            for _ in 0..<8 where !control.isHittable { app.swipeUp() }
            XCTAssertTrue(control.isHittable)
            let previous = control.value as? String == "1"
            if let enabled, previous != enabled {
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
                let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: control)
                XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            }
            app.buttons["Готово"].tap()
            return previous
        }
        let originalHistory = textHistory(false)
        defer {
            app.terminate(); app.launch()
            _ = textHistory(originalHistory)
            app.terminate()
        }
        func shot(_ name: String) {
            Thread.sleep(forTimeInterval: 1.5)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "store-ios-ru-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let textMode = app.segmentedControls.buttons["Текст"]
        XCTAssertTrue(textMode.waitForExistence(timeout: 90)); textMode.tap()
        let editor = app.textViews["Текст оригинала"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.tap(); editor.typeText("Подскажите, пожалуйста, как пройти к вокзалу?")
        if app.buttons["Скрыть клавиатуру"].exists { app.buttons["Скрыть клавиатуру"].tap() }
        let translate = app.buttons["text.translate"]
        XCTAssertTrue(translate.isEnabled); translate.tap()
        let result = app.staticTexts["text.translation.text"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            result.exists && result.label.lowercased().contains("station")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 180), .completed)
        shot("1-text")
        app.segmentedControls.buttons["Голос"].tap()
        let record = app.buttons["voice.record"]
        let prepare = app.buttons["voice.prepare"]
        if prepare.waitForExistence(timeout: 3) && prepare.isEnabled { prepare.tap() }
        XCTAssertTrue(record.waitForExistence(timeout: 180))
        shot("2-voice")
        app.buttons["Модели"].firstMatch.tap()
        XCTAssertTrue(app.buttons["models.languageSetup"].waitForExistence(timeout: 15))
        shot("3-models")
        app.buttons["models.languageSetup"].tap()
        XCTAssertTrue(app.textFields["setup.search.targets"].waitForExistence(timeout: 20))
        shot("4-languages")
    }

    /// Read-only screen traversal; caller verifies persisted preferences and history.
    @MainActor func testPublicationLocalizations() throws {
        guard ProcessInfo.processInfo.environment["KAT_IOS_LOCALIZATION_CHECK"] == "1" else {
            throw XCTSkip("Opt-in device localization acceptance")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate() }
        for (language, text, voice, models, settings, done) in [
            ("es", "Texto", "Voz", "Modelos", "Ajustes", "Hecho"),
            ("tr", "Metin", "Ses", "Modeller", "Ayarlar", "Tamamlandı")
        ] {
            app.launchArguments = ["-languageSetupCompleted", "YES", "-appInterfaceLanguage", language,
                "-AppleLanguages", "(\(language))", "-automaticModelLoad", "NO", "-showTechnicalInfo", "NO"]
            app.launch()
            func shot(_ screen: String) {
                Thread.sleep(forTimeInterval: 1.5) // Let mode/sheet transitions finish before capture.
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "acceptance-ios-\(language)-\(screen)"
                attachment.lifetime = .keepAlways; add(attachment)
            }
            let textMode = app.segmentedControls.buttons[text]
            XCTAssertTrue(textMode.waitForExistence(timeout: 60)); textMode.tap()
            XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["text.translate"].exists)
            shot("text")
            app.segmentedControls.buttons[voice].tap()
            shot("voice")
            app.buttons[settings].tap()
            XCTAssertTrue(app.buttons[done].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons[done].isHittable)
            shot("settings")
            app.buttons[done].tap()
            app.buttons[models].firstMatch.tap()
            let setup = app.buttons["models.languageSetup"]
            XCTAssertTrue(setup.waitForExistence(timeout: 10)); shot("models")
            setup.tap()
            XCTAssertTrue(app.textFields["setup.search.targets"].waitForExistence(timeout: 15))
            shot("languages")
            app.terminate()
        }
    }

    /// Exercise the compact-device Auto policy using installed OPUS and Index, without
    /// changing the saved device probe: the launch-domain value hides it for this process.
    @MainActor func testAutoOpusPickerAndDetectedTextSwitchingOnPhone() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
            "-appInterfaceLanguage", "en", "-deviceProbeResult", "",
            "-selectedTranslationModel", "opus-mt-big-en-zle-int8", "-translationSource", "ru", "-translationTarget", "en",
            "-automaticLanguage", "YES", "-automaticSpeechText", "NO", "-memorySaving", "NO",
            "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-historyRecordImages", "NO"]
        app.launch(); defer { app.terminate() }
        let textMode = app.segmentedControls.buttons["Text"]
        XCTAssertTrue(textMode.waitForExistence(timeout: 120)); textMode.tap()
        func selectedModel(_ ids: [String], enableAuto: Bool = false) {
            app.buttons["Models"].firstMatch.tap()
            XCTAssertTrue(app.buttons["model.select.auto"].waitForExistence(timeout: 15))
            // Launch arguments are strings; Auto's persisted preference is a Bool. Use
            // the real control instead of overriding that typed preference with "YES".
            if enableAuto { app.buttons["model.select.auto"].tap() }
            func selected() -> Bool { ids.contains { let item = app.buttons["model.select." + $0]; return item.exists && item.value as? String == "Selected" } }
            for _ in 0..<8 where !selected() { app.swipeUp() }
            XCTAssertTrue(selected(), app.debugDescription)
            app.buttons["sheet.done"].tap()
        }
        XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 120))
        selectedModel(["opus-mt-big-en-zle-int8"], enableAuto: true)
        XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 30))
        app.buttons["language.target"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Japanese")
        let japanese = app.buttons["language.option.ja"]
        XCTAssertTrue(japanese.waitForExistence(timeout: 10)); XCTAssertTrue(japanese.isEnabled)
        let picker = XCTAttachment(screenshot: app.screenshot()); picker.name = "auto-opus-allows-japanese"; picker.lifetime = .keepAlways; add(picker)
        endLanguageSearch(app); app.buttons["language.close"].tap()
        let cases = [("Der Zug nach Berlin fährt morgen um 07:45 ab.", ["index-translate-2b-q4km", "index-translate-9b-q4km"]),
                     ("Поезд до Москвы отправится завтра в 07:45.", ["opus-mt-big-en-zle-int8"])]
        for (text, models) in cases {
            let editor = app.textViews["Original text"]
            XCTAssertTrue(editor.waitForExistence(timeout: 15))
            if app.buttons["text.clear.source"].exists { app.buttons["text.clear.source"].tap() }
            editor.tap(); editor.typeText(text)
            if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
            app.buttons["text.translate"].tap()
            let result = app.staticTexts["text.translation.text"]
            let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                result.exists && result.label.localizedCaseInsensitiveContains("train") && result.label.contains("7:45")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 150), .completed, app.debugDescription)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "auto-model-" + models[0]; shot.lifetime = .keepAlways; add(shot)
            selectedModel(models)
        }
    }
    @MainActor func testAutomaticLanguageLivesInSourceMenuInEveryMode() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-automaticSpeechVoice", "NO", "-historyRecordImages", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.segmentedControls.buttons["Text"].waitForExistence(timeout: 60))
        app.segmentedControls.buttons["Text"].tap()
        XCTAssertTrue(app.buttons["language.source"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.switches["language.automatic"].exists)
        app.buttons["language.source"].tap()
        let auto = app.buttons["language.option.auto"]
        XCTAssertTrue(auto.waitForExistence(timeout: 10)); XCTAssertTrue(auto.isHittable)
        XCTAssertLessThan(auto.frame.minY, app.buttons["language.legend"].frame.minY)
        let sheetShot = XCTAttachment(screenshot: app.screenshot()); sheetShot.name = "ios-auto-first-row"; sheetShot.lifetime = .keepAlways; add(sheetShot)
        auto.tap()
        XCTAssertEqual(app.buttons["language.source"].value as? String, "auto")
        app.segmentedControls.buttons["Voice"].tap()
        XCTAssertFalse(app.switches["language.automatic"].exists)
        app.buttons["language.source"].tap()
        XCTAssertTrue(auto.waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("English")
        app.buttons["language.option.en"].tap()
        XCTAssertEqual(app.buttons["language.source"].value as? String, "en")
        app.segmentedControls.buttons["Camera"].tap()
        XCTAssertTrue(app.buttons["camera.close"].waitForExistence(timeout: 30))
        let cameraLanguagesReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["language.source"])
        XCTAssertEqual(XCTWaiter.wait(for: [cameraLanguagesReady], timeout: 90), .completed)
        app.buttons["language.source"].tap()
        XCTAssertTrue(auto.waitForExistence(timeout: 10)); auto.tap()
        XCTAssertTrue((app.buttons["language.source"].value as? String ?? "").hasPrefix("auto"))
        app.buttons["camera.close"].tap()
        XCTAssertEqual(app.buttons["language.source"].value as? String, "auto")
    }
    @MainActor func testPreparedVoiceReturnsAfterCamera() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru",
            "-automaticLanguage", "NO", "-automaticSpeechVoice", "NO", "-memorySaving", "NO",
            "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-historyRecordImages", "NO"]
        app.launch(); defer { app.terminate() }
        let prepare = app.buttons["voice.prepare"], record = app.buttons["voice.record"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 90)); prepare.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 90)); XCTAssertTrue(record.isEnabled)
        for _ in 0..<2 {
            app.segmentedControls.buttons["Camera"].tap()
            let shutter = app.buttons["camera.capture"]
            XCTAssertTrue(shutter.waitForExistence(timeout: 15))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: shutter)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
            app.buttons["camera.close"].tap()
            XCTAssertTrue(record.waitForExistence(timeout: 45), "Returning from Camera must restore a previously prepared Voice without another preparation tap")
            XCTAssertTrue(record.isEnabled); XCTAssertFalse(prepare.exists)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "voice-ready-after-camera"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testCameraDoesNotPreparePreviouslyUnloadedVoice() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru",
            "-automaticLanguage", "NO", "-memorySaving", "NO", "-historyRecordImages", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["voice.prepare"].waitForExistence(timeout: 90))
        app.segmentedControls.buttons["Camera"].tap()
        XCTAssertTrue(app.buttons["camera.close"].waitForExistence(timeout: 15))
        app.buttons["camera.close"].tap()
        XCTAssertTrue(app.buttons["voice.prepare"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.buttons["voice.record"].exists)
    }
    @MainActor func testShortGreetingAutomaticLanguageOnPhone() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "YES", "-automaticSpeechText", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.segmentedControls.buttons["Text"].waitForExistence(timeout: 60)); app.segmentedControls.buttons["Text"].tap()
        let editor = app.textViews["Original text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20)); editor.tap(); editor.typeText("Hello")
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        XCTAssertEqual(app.staticTexts["text.source.language"].label, "English")
        XCTAssertEqual(app.buttons["language.target"].value as? String, "ru")
        app.buttons["text.translate"].tap()
        let result = app.staticTexts["text.translation.text"]
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in result.exists && ["привет", "здравств"].contains(where: result.label.lowercased().contains) }, object: nil)
        let translationStatus = XCTWaiter.wait(for: [translated], timeout: 60)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "hello-auto-english-to-russian"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertEqual(translationStatus, .completed, "Output: \(result.debugDescription); UI: \(app.debugDescription)")
        app.buttons["language.target"].tap(); app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("English")
        XCTAssertTrue(app.buttons["language.option.en"].waitForExistence(timeout: 5)); app.buttons["language.option.en"].tap()
        XCTAssertEqual(app.staticTexts["text.source.language"].label, "English")
        app.buttons["text.translate"].tap()
        let sameLanguage = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in result.exists && result.label == "Hello" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [sameLanguage], timeout: 15), .completed)
        XCTAssertEqual(app.buttons["language.target"].value as? String, "en")
        app.buttons["text.clear.source"].tap(); editor.tap(); editor.typeText("gift")
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        XCTAssertEqual(app.staticTexts["text.source.language"].label, "Auto", "Unknown source must not display the old manual language")
    }
    @MainActor func testModelLanguageListsMatchPickerSupport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        for (model, count) in [("index-translate-9b-q4km", 150)] {
            app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", model, "-translationSource", "ru", "-translationTarget", "en", "-favoriteTranslationLanguages", "ban,id,ru,uk"]
            app.launch()
            XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 60))
            app.buttons["language.target"].tap()
            XCTAssertTrue(app.buttons["language.option.ru"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.buttons["language.option.ban"].exists, count == 152, "Unsupported favorites must be hidden")
            XCTAssertEqual(app.buttons["language.option.id"].exists, count != 14)
            XCTAssertEqual(app.buttons["language.option.uk"].exists, count == 150 || count == 152)
            let search = app.searchFields.firstMatch
            search.tap(); search.typeText("Balinese")
            if count == 152 { XCTAssertTrue(app.buttons["language.option.ban"].waitForExistence(timeout: 5)) }
            else {
                XCTAssertTrue(app.staticTexts["Language not found"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["language.option.ban"].exists)
            }
            endLanguageSearch(app)
            app.buttons["language.close"].tap()
            app.buttons["Models"].firstMatch.tap()
            let info = app.buttons["model.info." + model]
            for _ in 0..<5 { if info.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(info.waitForExistence(timeout: 10)); info.tap()
            let link = app.buttons["model.languages.open"]
            XCTAssertTrue(link.waitForExistence(timeout: 10))
            XCTAssertEqual(link.value as? String, String(count))
            link.tap()
            XCTAssertTrue(app.staticTexts["model.languages.count"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["model.languages.count"].label, "Translation languages in the app: \(count)")
            let listShot = XCTAttachment(screenshot: app.screenshot())
            listShot.name = "model-languages-list-" + model; listShot.lifetime = .keepAlways; add(listShot)
            let infoSearch = app.textFields["model.languages.search"]
            infoSearch.tap(); infoSearch.typeText("Balinese")
            let row = app.descendants(matching: .any).matching(identifier: "model.languages.row.ban").firstMatch
            if count == 152 { XCTAssertTrue(row.waitForExistence(timeout: 5)) }
            else { XCTAssertTrue(app.staticTexts["Language not found"].waitForExistence(timeout: 5)); XCTAssertFalse(row.exists) }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "model-languages-" + model; shot.lifetime = .keepAlways; add(shot)
            app.buttons["model.info.close"].tap()
            app.buttons["sheet.done"].tap()
            XCTAssertEqual(app.buttons["language.target"].value as? String, "en")
            app.terminate()
        }
    }
    @MainActor func testCenteredProcessingOverlayCancelsAndRevealsResult() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch(); defer { app.terminate() }
        let mode = app.segmentedControls.buttons["Text"]
        XCTAssertTrue(mode.waitForExistence(timeout: 60)); mode.tap()
        let editor = app.textViews["Original text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        for _ in 0..<4 where !editor.isHittable { app.swipeUp() }
        editor.tap()
        editor.typeText("The library opens at nine in the morning. Visitors can read books, use the computers, and ask the staff for help. On Saturday, children and their parents meet upstairs to discuss stories. Please bring your library card if you want to borrow a book. The cafe serves tea and fresh bread. After the meeting, we will walk through the park and take the bus home.")
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        app.buttons["text.translate"].tap()
        let cancel = app.buttons["processing.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 90)); XCTAssertTrue(cancel.isHittable)
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        XCTAssertEqual(cancel.frame.midX, app.frame.midX, accuracy: 3)
        let loading = XCTAttachment(screenshot: app.screenshot()); loading.name = "centered-processing-iphone"; loading.lifetime = .keepAlways; add(loading)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.buttons["text.translate"].isEnabled)
        app.buttons["text.translate"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 90))
        XCTAssertTrue(app.buttons["text.copy.target"].isEnabled)
        let result = XCTAttachment(screenshot: app.screenshot()); result.name = "processing-result-iphone"; result.lifetime = .keepAlways; add(result)
    }
    @MainActor func testTranslationTimingFitsPhoneAndClearsWithResult() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-showTechnicalInfo", "YES",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-memorySaving", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.segmentedControls.buttons["Text"].waitForExistence(timeout: 60))
        let prepare = app.buttons["voice.prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 90))
        XCTAssertEqual(prepare.label, "Translate")
        app.segmentedControls.buttons["Text"].tap()
        let action = app.buttons["text.translate"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertEqual(action.label, "Translate")
        XCTAssertFalse(action.isEnabled)
        let empty = XCTAttachment(screenshot: app.screenshot()); empty.name = "translate-empty-disabled"; empty.lifetime = .keepAlways; add(empty)
        let timing = app.staticTexts["text.timing"]
        XCTAssertFalse(timing.exists)
        let editor = app.textViews["Original text"]
        for _ in 0..<4 where !editor.isHittable { app.swipeUp() }
        XCTAssertTrue(editor.isHittable); editor.tap(); editor.typeText("Please bring a glass of water without sugar.")
        XCTAssertTrue(action.isEnabled)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        let keyboard = XCTAttachment(screenshot: app.screenshot()); keyboard.name = "translate-keyboard"; keyboard.lifetime = .keepAlways; add(keyboard)
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        let enabled = XCTAttachment(screenshot: app.screenshot()); enabled.name = "translate-enabled"; enabled.lifetime = .keepAlways; add(enabled)
        // One tap prepares an unloaded model and then translates the input.
        action.tap()
        XCTAssertTrue(timing.waitForExistence(timeout: 90))
        for _ in 0..<4 where !timing.isHittable { app.swipeUp() }
        XCTAssertTrue(timing.label.hasPrefix("Translation: "))
        XCTAssertGreaterThanOrEqual(timing.frame.minX, 0)
        XCTAssertLessThanOrEqual(timing.frame.maxX, app.frame.maxX)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "translation-timing-iphone"; shot.lifetime = .keepAlways; add(shot)
        let clear = app.buttons["text.clear.target"]
        XCTAssertTrue(clear.isHittable); clear.tap()
        XCTAssertFalse(timing.exists)
        let clearSource = app.buttons["text.clear.source"]
        for _ in 0..<4 where !clearSource.isHittable { app.swipeDown() }
        clearSource.tap()
        XCTAssertEqual(action.label, "Translate")
        XCTAssertFalse(action.isEnabled)
        let cleared = XCTAttachment(screenshot: app.screenshot()); cleared.name = "translate-prepared-empty"; cleared.lifetime = .keepAlways; add(cleared)
    }
    /// Catches truncation/duplication and loss of readiness across repeated 8K inference.
    /// Uses the production app/backend; argument-domain settings do not alter saved preferences.
    @MainActor func testFullscreenReaderAndCharacterCounts() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-appInterfaceLanguage", "en", "-AppleLanguages", "(en)", "-automaticModelLoad", "NO"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        let mode = app.segmentedControls.buttons["Text"]
        XCTAssertTrue(mode.waitForExistence(timeout: 60)); mode.tap()
        let expand = app.buttons["text.source.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 90)); XCTAssertFalse(expand.isEnabled)
        let editor = app.textViews.firstMatch
        for _ in 0..<4 { if editor.isHittable { break }; app.swipeUp() }
        let fixture = "Hello, world! Reading a translation should be comfortable."
        editor.tap(); editor.typeText(fixture)
        app.buttons["Hide keyboard"].tap()
        XCTAssertTrue(expand.isEnabled)
        XCTAssertLessThanOrEqual(expand.frame.maxX, app.buttons["text.source.playback.speed"].frame.minX)
        XCTAssertEqual(app.staticTexts["text.source.count"].label, "Characters: \(fixture.count)")
        expand.tap()
        let close = app.buttons["reader.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.text"].label, fixture)
        XCTAssertEqual(app.staticTexts["reader.count"].label, "Characters: \(fixture.count)")
        XCTAssertGreaterThan(app.scrollViews["reader.scroll"].frame.height, app.frame.height * 0.75)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "fullscreen-text-reader-iphone"; shot.lifetime = .keepAlways; add(shot)
        close.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, fixture)
    }
    @MainActor func testInAppInterfaceLanguage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        let settings = app.buttons.matching(NSPredicate(format: "label == 'Settings' OR label == 'Настройки'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 60))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: settings)], timeout: 90), .completed)
        settings.tap()
        let picker = app.buttons["settings.interfaceLanguage"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let original = picker.value as? String ?? "System default"
        func choose(_ english: String, _ russian: String) {
            picker.tap()
            let options = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", english, russian))
            options.element(boundBy: options.count - 1).tap()
        }
        choose("Russian", "Русский")
        XCTAssertTrue(app.staticTexts["Управление записью"].waitForExistence(timeout: 5))
        let russian = XCTAttachment(screenshot: app.screenshot()); russian.name = "settings-russian"; russian.lifetime = .keepAlways; add(russian)
        choose("English", "English")
        XCTAssertTrue(app.staticTexts["Recording controls"].waitForExistence(timeout: 5))
        if original == "Russian" || original == "Русский" { choose("Russian", "Русский") }
        else if original != "English" { choose("System default", "Как в системе") }
    }
    @MainActor func testSettingsRecordingMenuAndCopyVersion() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        let settings = app.buttons.matching(NSPredicate(format: "label == 'Settings' OR label == 'Настройки'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 60)); settings.tap()
        let mode = app.buttons["settings.recordingMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.tap()
        let hold = app.buttons.matching(NSPredicate(format: "label == 'Hold to record' OR label == 'Удерживать для записи'")).firstMatch
        let toggle = app.buttons.matching(NSPredicate(format: "label == 'Tap to start / stop' OR label == 'Нажать для старта / остановки'")).firstMatch
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.exists)
        // Close the menu without modifying the current recording mode.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        let copy = app.buttons["settings.copyVersion"]
        for _ in 0..<12 { if copy.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(copy.isHittable)
        XCTAssertNotNil((copy.value as? String)?.range(of: "ios-[0-9a-f]{16}", options: .regularExpression))
        copy.tap()
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Copied' OR value == 'Скопировано'"), object: copy)
        XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 2), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "settings-copy-version"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testRecognitionPickerAndNeonSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-automaticModelLoad", "NO"]
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        app.launch()
        let settings = app.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 60))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: settings)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        let main = XCTAttachment(screenshot: app.screenshot()); main.name = "neon-main"; main.lifetime = .keepAlways; add(main)
        settings.tap()
        let first = app.buttons["settings.recognition.whisper"]
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)), withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings.recognition.whisperKit"].exists)
        XCTAssertFalse(app.buttons["settings.recognition.apple"].exists)
        for choice in ["ultra", "whisper", "automatic"] {
            let option = app.buttons["settings.recognition." + choice]
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: option)
            let result = XCTWaiter.wait(for: [selected], timeout: 5)
            let state = XCTAttachment(screenshot: app.screenshot()); state.name = "recognizer-" + choice; state.lifetime = .keepAlways; add(state)
            XCTAssertEqual(result, .completed, "Selection must update to \(choice)")
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "neon-settings-recognizer"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testRecordingStopsOnFirstTapAfterPreparation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-appInterfaceLanguage", "ru", "-AppleLanguages", "(ru)", "-automaticModelLoad", "YES", "-unfinishedAutomaticModelLoad", "ui-test", "-selectedTranslationModel", "index-translate-9b-q4km", "-recordingPreprocessing", "NO", "-memorySaving", "NO", "-recordingMode", "toggle", "-recordingSilenceSeconds", "30", "-translationSource", "ru", "-translationTarget", "en", "-automaticLanguage", "YES", "-automaticSpeechVoice", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        defer { app.terminate(); app.launchArguments = []; app.launchEnvironment = [:]; app.launch() }
        app.launchEnvironment["OT_RECORDING_STOP_TRACE"] = "1"
        app.launch()
        let record = app.buttons["voice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 180))
        XCTAssertEqual(record.frame.midX, app.frame.midX, accuracy: 3)
        XCTAssertGreaterThanOrEqual(record.frame.width, 140)
        XCTAssertLessThan(record.frame.maxY, app.frame.maxY - 70)
        XCTAssertFalse(app.staticTexts["Нажмите для записи"].exists)
        let initial = XCTAttachment(screenshot: app.screenshot()); initial.name = "voice-centered-iphone"; initial.lifetime = .keepAlways; add(initial)
        for attempt in 0..<2 {
            record.tap()
            XCTAssertTrue(app.buttons["voice.pauseResume"].waitForExistence(timeout: 20))
            XCTAssertEqual(record.label, "Завершить запись")
            print("RECORD_STOP_CAPTURE_ACTIVE_\(attempt)")
            Thread.sleep(forTimeInterval: 8)
            XCTAssertEqual(record.label, "Завершить запись", "Capture must still be active before the stop tap")
            let began = Date()
            record.tap() // Exactly once: no retry and no automatic silence stop.
            let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !app.buttons["voice.pauseResume"].exists
            }, object: nil)
            let result = XCTWaiter.wait(for: [stopped], timeout: 2)
            let evidence = XCTAttachment(string: "Attempt \(attempt + 1), tap-to-recording-controls-gone: \(Date().timeIntervalSince(began)) s, result: \(result.rawValue)")
            evidence.lifetime = .keepAlways; add(evidence)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "single-stop-\(attempt)"; shot.lifetime = .keepAlways; add(shot)
            XCTAssertEqual(result, .completed, "One stop tap must end recording without waiting for silence")
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Настройки"])
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 60), .completed)
        }
    }

    @MainActor func testCompactTextCardHeader() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-automaticModelLoad", "NO", "-translationSource", "ru", "-translationTarget", "en"]
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        app.launch()
        XCTAssertTrue(app.buttons["Подготовить перевод"].waitForExistence(timeout: 30))
        app.segmentedControls.buttons["Текст"].tap()
        let editor = app.textViews["Текст оригинала"]
        for _ in 0..<5 { if editor.isHittable { break }; app.swipeUp() }
        editor.tap(); editor.typeText("Проверяем компактную строку кнопок.")
        app.buttons["Скрыть клавиатуру"].tap()
        let sourceIDs = ["text.source.playback.speed", "text.source.playback.startStop", "text.copy.source", "text.clear.source"]
        let source = sourceIDs.map { app.buttons[$0] }
        for _ in 0..<5 { if source[0].isHittable { break }; app.swipeDown() }
        for button in source {
            XCTAssertTrue(button.exists)
            XCTAssertEqual(button.frame.midY, source[0].frame.midY, accuracy: 1)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        }
        for index in 1..<source.count { XCTAssertGreaterThanOrEqual(source[index].frame.minX, source[index - 1].frame.maxX) }
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "compact-card-header"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor func testCachedStartupAndSpeakerStop() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-automaticModelLoad", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-automaticSpeechText", "NO", "-automaticLanguage", "NO", "-translationSource", "ru", "-translationTarget", "en"]
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        for pass in 0..<2 {
            let started = Date()
            app.launch()
            let ready = app.buttons["Подготовить перевод"]
            XCTAssertTrue(ready.waitForExistence(timeout: pass == 0 ? 240 : 30))
            let report = XCTAttachment(string: "restore pass \(pass): \(Date().timeIntervalSince(started)) seconds including app launch")
            report.name = "startup-cache-\(pass)"; report.lifetime = .keepAlways; add(report)
            if pass == 0 { app.terminate() }
        }
        app.segmentedControls.buttons["Текст"].tap()
        let editor = app.textViews["Текст оригинала"]
        for _ in 0..<5 { if editor.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(editor.isHittable)
        editor.tap()
        editor.typeText("Здравствуйте. Мы хотели бы заказать ужин и узнать, во сколько завтра открывается ресторан. Пожалуйста, расскажите о меню и свободных столиках на вечер.")
        app.buttons["Скрыть клавиатуру"].tap()
        let speaker = app.buttons["text.source.playback.startStop"]
        for _ in 0..<5 { if speaker.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(speaker.isHittable); speaker.tap()
        XCTAssertTrue(app.staticTexts["Озвучиваю…"].waitForExistence(timeout: 180), "Wait for actual playback, not just a pending read request")
        let pause = app.buttons["text.source.playback.pauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 180))
        XCTAssertEqual(speaker.label, "Остановить озвучку")
        XCTAssertTrue(speaker.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "speaker-stop-visible"; shot.lifetime = .keepAlways; add(shot)
        speaker.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pause)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(speaker.label, "Озвучить оригинал")
    }

    @MainActor func testDownloadValidationCleanup() throws {
        guard ProcessInfo.processInfo.environment["OT_DOWNLOAD_VALIDATION_BUILD"] == "1" else { throw XCTSkip("Opt-in fixture cleanup") }
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO"]
        app.launchEnvironment["OT_DOWNLOAD_VALIDATION"] = "cleanup"
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.staticTexts["download-probe-cleaned"].waitForExistence(timeout: 30))
    }
    @MainActor func testBackgroundDownloadValidation() throws {
        guard ProcessInfo.processInfo.environment["OT_DOWNLOAD_VALIDATION_BUILD"] == "1" else { throw XCTSkip("Opt-in small download integration fixture") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO"]
        app.launchEnvironment["OT_DOWNLOAD_VALIDATION"] = "1"
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.staticTexts["download-probe-running"].waitForExistence(timeout: 100))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Notification Center presents the same Live Activity view as the Lock Screen.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.01)).press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.85)))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "download-live-activity"; shot.lifetime = .keepAlways; add(shot)
        Thread.sleep(forTimeInterval: 45)
        app.activate()
        XCTAssertTrue(app.staticTexts["download-probe-complete"].waitForExistence(timeout: 140))
    }
    @MainActor func testLanguageSetupDependenciesAndSearch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        for english in [false, true] {
            app.launchArguments = ["-AppleLanguages", english ? "(en)" : "(ru)", "-automaticModelLoad", "NO", "-translationSource", "ru", "-translationTarget", "en"]
            app.launch()
            // The in-app interface language can override -AppleLanguages.
            let models = app.buttons.matching(NSPredicate(format: "label IN %@", ["Модели", "Models"])).firstMatch
            XCTAssertTrue(models.waitForExistence(timeout: 120)); models.tap()
            let setup = app.buttons["models.languageSetup"]
            XCTAssertTrue(setup.waitForExistence(timeout: 10)); setup.tap()
            XCTAssertTrue(app.textFields["setup.search.targets"].waitForExistence(timeout: 10))
            let voice = app.switches["setup.recognition"]
            XCTAssertEqual(voice.value as? String, "1")
            XCTAssertEqual(app.switches["setup.speech"].value as? String, "1")
            let search = app.textFields["setup.search.targets"]
            search.tap(); search.typeText("th")
            let thai = app.buttons["setup.target.th"]
            XCTAssertTrue(thai.waitForExistence(timeout: 5)); thai.tap()
            app.swipeUp()
            let kit = app.descendants(matching: .any).matching(identifier: "setup.asr.whisper-large-v3-turbo-f16").firstMatch
            for _ in 0..<4 where !kit.isHittable { app.swipeUp() }
            XCTAssertTrue(kit.exists)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = english ? "language-setup-en" : "language-setup-ru"; shot.lifetime = .keepAlways; add(shot)
            // Dismiss without saving or downloading; the test preserves installed models and user choices.
            app.buttons.matching(NSPredicate(format: "label IN %@", ["Позже", "Later"])).firstMatch.tap()
            app.terminate()
        }
    }
    /// Line starts on a panel screen: every element that begins a line must start on a text edge
    /// shared with other lines. A lone start 4–24 pt off the nearest edge is the "not quite even"
    /// look (extra button insets, stray padding); larger offsets are icons or nested content.
    @MainActor private func misalignedLineStarts(_ app: XCUIApplication, in scope: XCUIElement, screen: String) -> [String] {
        let bounds = app.windows.firstMatch.frame
        // Scoped to the sheet: the screen underneath stays in the accessibility tree.
        let items = (scope.staticTexts.allElementsBoundByIndex + scope.buttons.allElementsBoundByIndex + scope.switches.allElementsBoundByIndex)
            .map { ($0.label, $0.frame) }
            .filter { !$0.1.isEmpty && $0.1.width < bounds.width - 1 && $0.1.minY >= bounds.minY + 100 && $0.1.maxY <= bounds.maxY - 40 && $0.1.minX < bounds.midX }
        func overlaps(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) / 2 }
        // Row buttons whose label holds other texts are containers, not line content.
        // A list row that holds a single text reports the whole cell frame; it says nothing about insets.
        let cells = scope.cells.allElementsBoundByIndex.map(\.frame)
        let leaves = items.filter { item in !items.contains { $0.1 != item.1 && item.1.contains($0.1) }
            && !cells.contains { abs($0.minX - item.1.minX) < 1 && abs($0.width - item.1.width) < 1 } }
        let starts = leaves.filter { item in !leaves.contains { $0.1 != item.1 && overlaps($0.1, item.1) && $0.1.minX < item.1.minX - 1 } }
        // Text edges are line starts shared by at least two lines (cards and nested panels each
        // have one); a lone start a few points off the nearest edge is the misalignment.
        let counts = Dictionary(grouping: starts) { Int($0.1.minX.rounded()) }.mapValues(\.count)
        let edges = counts.filter { $0.value >= 2 }.keys
        return starts.compactMap { item in
            let x = Int(item.1.minX.rounded())
            guard counts[x] == 1, let edge = edges.min(by: { abs($0 - x) < abs($1 - x) }) else { return nil }
            let offset = x - edge
            // 4 pt tolerance: SF Symbols in Labels carry a few points of side bearing.
            return abs(offset) > 4 && abs(offset) < 24 ? "\(screen): «\(item.0.prefix(50))» starts \(offset) pt from the text edge (x \(x), edge \(edge), y \(Int(item.1.minY)))" : nil
        }
    }

    /// Rightmost x (points) of the lime accent on one screenshot row, scanning right from `from`.
    private func rightmostAccentX(_ image: UIImage, y: CGFloat, from: CGFloat) -> CGFloat? {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let scale = CGFloat(cg.width) / image.size.width, row = Int(y * scale), stride = cg.bytesPerRow, step = cg.bitsPerPixel / 8
        guard row >= 0, row < cg.height, step >= 3 else { return nil }
        let bgr = cg.bitmapInfo.contains(.byteOrder32Little)
        var found: Int?
        for x in Int(from * scale)..<cg.width {
            let o = row * stride + x * step
            let (r, g, b) = bgr ? (bytes[o + 2], bytes[o + 1], bytes[o]) : (bytes[o], bytes[o + 1], bytes[o + 2])
            if g > 200 && r > 150 && b < 120 { found = x }
        }
        return found.map { CGFloat($0 + 1) / scale }
    }

    /// Read-only audit of the Models and language setup screens; nothing is downloaded or saved.
    @MainActor func testPanelScreensAlignLineStarts() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        app.launchArguments = ["-automaticModelLoad", "NO"]
        app.launch()
        var problems = Set<String>()
        let models = app.buttons.matching(NSPredicate(format: "label IN %@", ["Модели", "Models"])).firstMatch
        XCTAssertTrue(models.waitForExistence(timeout: 120)); models.tap()
        let setup = app.buttons["models.languageSetup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        for step in 0..<10 {
            let found = misalignedLineStarts(app, in: app.collectionViews.containing(.button, identifier: "models.languageSetup").firstMatch, screen: "models")
            if !found.isEmpty { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "audit-models-problem-\(step)"; shot.lifetime = .keepAlways; add(shot) }
            problems.formUnion(found)
            if step == 0 { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "audit-models"; shot.lifetime = .keepAlways; add(shot) }
            app.swipeUp()
        }
        for _ in 0..<12 where !setup.isHittable { app.swipeDown() }
        setup.tap()
        XCTAssertTrue(app.textFields["setup.search.targets"].waitForExistence(timeout: 30))
        // Side-by-side actions share one width (an inactive Download once rendered as bare text).
        let done = app.buttons["setup.done"], download = app.buttons["setup.download"]
        if done.exists { XCTAssertEqual(done.frame.width, download.frame.width, accuracy: 1, "Download and Done widths differ") }
        // Sizes use the app language, not the system one (an English UI once showed «ГБ»).
        let english = app.staticTexts["Your languages"].exists || app.navigationBars["Your languages"].exists
        let foreignUnits = english ? ["ГБ", "МБ", "КБ"] : [" GB", " MB", " KB"]
        let sizes = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { label in foreignUnits.contains { label.contains($0) } }
        XCTAssertTrue(sizes.isEmpty, "Units in the other language: \(sizes.prefix(3))")
        let panel = app.otherElements["setup.panel.models"], bar = app.otherElements["setup.bar"]
        XCTAssertTrue(panel.exists && bar.exists, "Setup panels must be reachable by identifier")
        for step in 0..<4 {
            // Toggles stay within the width of the cards above and below them.
            // The system switch draws its track beyond its frame, so measure the drawn pixels.
            let screen = app.screenshot().image
            for toggle in [app.switches["setup.recognition"], app.switches["setup.speech"]] where toggle.exists && toggle.frame.minY > 100 && toggle.frame.maxY < bar.frame.minY {
                if let drawn = rightmostAccentX(screen, y: toggle.frame.midY, from: toggle.frame.midX), drawn > panel.frame.maxX + 1 {
                    problems.insert("setup: toggle drawn \(Int(drawn - panel.frame.maxX)) pt right of the cards")
                }
            }
            problems.formUnion(misalignedLineStarts(app, in: app.scrollViews.containing(.textField, identifier: "setup.search.targets").firstMatch, screen: "setup"))
            if step == 0 { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "audit-setup"; shot.lifetime = .keepAlways; add(shot) }
            app.swipeUp()
        }
        // Scrolled to the end, the bottom bar covers no control.
        for _ in 0..<4 { app.swipeUp() }
        // Sizes in the models card sit at its right text edge, as on Mac.
        for size in panel.staticTexts.matching(identifier: "setup.size").allElementsBoundByIndex {
            if abs(panel.frame.maxX - 16 - size.frame.maxX) > 2 { problems.insert("setup: size «\(size.label)» ends \(Int(panel.frame.maxX - 16 - size.frame.maxX)) pt left of the card edge") }
        }
        // Scrolled to the end, the content (the models card and the notes under it) clears the bottom bar.
        let last = app.scrollViews.containing(.textField, identifier: "setup.search.targets").firstMatch.staticTexts.allElementsBoundByIndex.last
        if let last, bar.exists, last.frame.maxY > bar.frame.minY { problems.insert("setup: bottom bar covers «\(last.label.prefix(40))»") }
        if panel.exists, bar.exists, panel.frame.maxY > bar.frame.minY { problems.insert("setup: bottom bar covers the models card") }
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
    }
    /// Opens the OPUS directions screen, selects one hosted direction and checks the total;
    /// nothing is downloaded and the selection is not saved.
    @MainActor func testOpusDirectionsSelectionShowsTotal() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        app.launchArguments = ["-automaticModelLoad", "NO"]
        app.launch()
        // The in-app interface language may override the system one.
        let models = app.buttons.matching(NSPredicate(format: "label IN %@", ["Модели", "Models"])).firstMatch
        XCTAssertTrue(models.waitForExistence(timeout: 120)); models.tap()
        let open = app.buttons["opus.directions.open"]
        XCTAssertTrue(app.buttons["models.languageSetup"].waitForExistence(timeout: 10))
        // The list is lazy: the row exists only after scrolling to it.
        // Frame check, not isHittable: an off-screen row has no activation point and throws.
        let window = app.windows.firstMatch.frame
        func onScreen() -> Bool { open.exists && open.frame.minY > window.minY + 100 && open.frame.maxY < window.maxY - 80 }
        for _ in 0..<12 where !onScreen() { app.swipeUp() }
        XCTAssertTrue(onScreen()); open.tap()
        let total = app.staticTexts["opus.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(total.label.hasSuffix(": 0"), total.label)
        let search = app.textFields["opus.search"]
        search.tap(); search.typeText("de")
        let direction = app.buttons["opus.direction.de-ru"]
        XCTAssertTrue(direction.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "opus-directions"; shot.lifetime = .keepAlways; add(shot)
        guard direction.isEnabled else { return } // already installed
        let before = direction.value as? String
        direction.tap()
        XCTAssertTrue(total.label.hasSuffix(": 1"), total.label)
        XCTAssertNotEqual(direction.value as? String, before)
        let selected = XCTAttachment(screenshot: app.screenshot()); selected.name = "opus-directions-selected"; selected.lifetime = .keepAlways; add(selected)
        direction.tap()
        XCTAssertTrue(total.label.hasSuffix(": 0"), total.label)
    }
    @MainActor func testHybridRecognitionPackagesAreReadyInBothUILanguages() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        for english in [false, true] {
            let code = english ? "en" : "ru"
            app.launchArguments = ["-AppleLanguages", "(\(code))", "-automaticModelLoad", "NO"]
            app.launch()
            let models = app.buttons[english ? "Models" : "Модели"]
            XCTAssertTrue(models.waitForExistence(timeout: 120)); models.tap()
            // Restoring every installed voice/model continues after this sheet opens.
            XCTAssertTrue(app.staticTexts[english ? "Translation packages are ready" : "Пакеты для перевода готовы"].waitForExistence(timeout: 180))
            for id in ["asr-parakeet-ultra", "whisper-large-v3-turbo-f16"] {
                let ready = app.descendants(matching: .any).matching(identifier: "model.installed." + id).firstMatch
                for _ in 0..<14 { if ready.exists && ready.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(ready.exists); XCTAssertTrue(ready.isHittable)
                XCTAssertFalse(app.buttons["model.download." + id].exists)
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "recognition-" + id + "-" + code; shot.lifetime = .keepAlways; add(shot)
            }
            app.terminate()
        }
    }
    @MainActor func testPrivacyAndRecordingPreviewSetting() throws {
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        for english in [false, true] {
            app.launchArguments = ["-AppleLanguages", english ? "(en)" : "(ru)", "-automaticModelLoad", "NO"]
            app.launch()
            XCTAssertFalse(app.buttons["toolbar.diagnostics"].exists)
            app.buttons[english ? "Settings" : "Настройки"].tap()
            XCTAssertTrue(app.staticTexts[english ? "Recording controls" : "Управление записью"].waitForExistence(timeout: 10))
            let top = XCTAttachment(screenshot: app.screenshot()); top.name = english ? "settings-top-en" : "settings-top-ru"; top.lifetime = .keepAlways; add(top)
            let preview = app.switches["settings.recordingPreprocessing"]
            for _ in 0..<4 where !preview.isHittable { app.swipeUp() }
            XCTAssertTrue(preview.exists)
            let previewWasOn = preview.value as? String == "1"
            if !previewWasOn { preview.switches.firstMatch.tap() }
            XCTAssertEqual(preview.value as? String, "1")
            let verification = app.switches["settings.recordingPreviewVerification"]
            for _ in 0..<3 where !verification.isHittable { app.swipeUp() }
            XCTAssertTrue(verification.exists)
            XCTAssertEqual(verification.value as? String, "1")
            verification.switches.firstMatch.tap(); XCTAssertEqual(verification.value as? String, "0")
            verification.switches.firstMatch.tap(); XCTAssertEqual(verification.value as? String, "1")
            let experiment = XCTAttachment(screenshot: app.screenshot()); experiment.name = english ? "settings-experiment-en" : "settings-experiment-ru"; experiment.lifetime = .keepAlways; add(experiment)
            if !previewWasOn { preview.switches.firstMatch.tap() }
            let privacy = app.buttons["settings.privacy"]
            for _ in 0..<10 where !privacy.isHittable { app.swipeUp() }
            XCTAssertTrue(app.staticTexts["settings.version"].exists || app.otherElements["settings.version"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = english ? "about-en" : "about-ru"; shot.lifetime = .keepAlways; add(shot)
            let diagnostics = app.switches["settings.showTechnicalInfo"]
            XCTAssertTrue(diagnostics.exists)
            XCTAssertEqual(diagnostics.value as? String, "0")
            diagnostics.switches.firstMatch.tap()
            app.buttons[english ? "Done" : "Готово"].firstMatch.tap()
            XCTAssertTrue(app.buttons["toolbar.diagnostics"].waitForExistence(timeout: 5))
            app.buttons[english ? "Settings" : "Настройки"].tap()
            for _ in 0..<12 where !diagnostics.isHittable { app.swipeUp() }
            diagnostics.switches.firstMatch.tap()
            app.buttons[english ? "Done" : "Готово"].firstMatch.tap()
            XCTAssertFalse(app.buttons["toolbar.diagnostics"].exists)
            app.buttons[english ? "Settings" : "Настройки"].tap()
            for _ in 0..<12 where !privacy.isHittable { app.swipeUp() }
            privacy.tap()
            XCTAssertTrue(app.staticTexts[english ? "On-device processing" : "Обработка на устройстве"].waitForExistence(timeout: 5))
            let policy = XCTAttachment(screenshot: app.screenshot()); policy.name = english ? "privacy-en" : "privacy-ru"; policy.lifetime = .keepAlways; add(policy)
            app.terminate()
        }
    }
    @MainActor func testRecordingPreviewShortCaptureCanRestart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OT_TTS_MEMORY_TRACE"] = "1"
        // A prior interrupted developer run may leave the intentional startup crash guard.
        // Override it only in this test's argument domain; normal app behavior is unchanged.
        app.launchArguments = ["-AppleLanguages", "(ru)", "-automaticModelLoad", "YES", "-unfinishedAutomaticModelLoad", "ui-test", "-selectedTranslationModel", "qwen35-9b-q4km", "-recordingPreprocessing", "YES", "-memorySaving", "NO", "-recordingMode", "toggle", "-translationSource", "ru", "-translationTarget", "en", "-automaticLanguage", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        defer { app.terminate(); app.launchArguments = []; app.launchEnvironment = [:]; app.launch() }
        app.launch()
        let record = app.buttons["voice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 180))
        for _ in 0..<2 {
            record.tap()
            let pause = app.buttons["voice.pauseResume"]
            XCTAssertTrue(pause.waitForExistence(timeout: 10))
            record.tap()
            let ready = NSPredicate(format: "enabled == true")
            expectation(for: ready, evaluatedWith: app.buttons["Настройки"])
            waitForExpectations(timeout: 45)
        }
    }
    @MainActor private func endLanguageSearch(_ app: XCUIApplication) {
        // iOS temporarily replaces the sheet's Done toolbar while the search field is active.
        for label in ["Close", "Cancel", "Закрыть", "Отменить", "Отмена"] {
            let cancel = app.buttons[label].firstMatch
            if cancel.exists { cancel.tap(); return }
        }
    }

    @MainActor func testRussianEnglishInterfaceAndAlignedLanguageIcons() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        func screenshot(_ name: String) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        for english in [false, true] {
            app.terminate()
            let code = english ? "en" : "ru"
            app.launchArguments = ["-AppleLanguages", "(\(code))", "-AppleLocale", english ? "en_US" : "ru_RU", "-automaticModelLoad", "NO", "-showTechnicalInfo", "YES"] + ["-showTechnicalInfo", "YES"]
            app.launch()
            XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 120))
            let source = app.buttons["language.source"].value as? String
            let target = app.buttons["language.target"].value as? String
            let selectedModel = app.staticTexts["model.current"].label
            XCTAssertTrue(app.buttons[english ? "Voice" : "Голос"].exists)
            app.buttons[english ? "Text" : "Текст"].tap()
            XCTAssertTrue(app.buttons["text.translate"].exists)
            screenshot(code + "-text")
            app.buttons[english ? "Voice" : "Голос"].tap()
            app.buttons[english ? "Settings" : "Настройки"].tap()
            XCTAssertTrue(app.staticTexts[english ? "Recording controls" : "Управление записью"].waitForExistence(timeout: 10))
            screenshot(code + "-settings")
            app.buttons[english ? "Voices and samples" : "Голоса и образцы"].tap()
            XCTAssertTrue(app.navigationBars[english ? "Voices" : "Голоса"].waitForExistence(timeout: 10))
            screenshot(code + "-voices")
            app.navigationBars[english ? "Voices" : "Голоса"].buttons.firstMatch.tap()
            app.buttons[english ? "Done" : "Готово"].firstMatch.tap()
            app.buttons[english ? "Models" : "Модели"].tap()
            XCTAssertTrue(app.staticTexts[english ? "Translation model" : "Модель перевода"].waitForExistence(timeout: 10))
            screenshot(code + "-models")
            app.buttons[english ? "Done" : "Готово"].firstMatch.tap()
            app.buttons[english ? "Report and measurements" : "Отчёт и измерения"].tap()
            XCTAssertTrue(app.staticTexts[english ? "Current resources" : "Ресурсы сейчас"].waitForExistence(timeout: 10))
            screenshot(code + "-diagnostics")
            app.buttons[english ? "Done" : "Готово"].firstMatch.tap()
            let queries = english ? [("Русский", "ru")] : [("Болгарский", "bg"), ("Верхнелужицкий", "hsb"), ("Гаитянский", "ht"), ("Валлийский", "cy")]
            var columnX: [CGFloat]?
            for (query, id) in queries {
                app.buttons["language.target"].tap()
                let search = app.searchFields.firstMatch
                XCTAssertTrue(search.waitForExistence(timeout: 10))
                search.tap()
                if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { search.tap() }
                search.typeText(query)
                XCTAssertTrue(app.buttons["language.option." + id].waitForExistence(timeout: 10))
                let mic = app.images["language.speech." + id]
                let voice = app.buttons["language.voice." + id]
                let favorite = app.buttons["language.favorite." + id]
                XCTAssertTrue(mic.exists)
                XCTAssertEqual(mic.frame.midY, voice.frame.midY, accuracy: 2)
                XCTAssertEqual(voice.frame.midY, favorite.frame.midY, accuracy: 2)
                let positions = [mic.frame.midX, voice.frame.midX, favorite.frame.midX]
                if let columnX { for index in 0..<3 { XCTAssertEqual(columnX[index], positions[index], accuracy: 2) } }
                columnX = positions
                screenshot(code + "-language-" + id)
                endLanguageSearch(app)
                app.buttons["language.close"].tap()
            }
            XCTAssertEqual(app.buttons["language.source"].value as? String, source)
            XCTAssertEqual(app.buttons["language.target"].value as? String, target)
            XCTAssertEqual(app.staticTexts["model.current"].label, selectedModel)
        }
    }

    @MainActor func testLanguageCapabilityIcons() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-languageSetupCompleted", "YES", "-appInterfaceLanguage", "ru", "-selectedTranslationModel", "qwen35-9b-q4km"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 120))
        app.buttons["language.target"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "language-capabilities-list"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["language.legend"].tap()
        XCTAssertTrue(app.staticTexts["Озвучка доступна — голос нужно скачать"].waitForExistence(timeout: 5))
        let legend = XCTAttachment(screenshot: app.screenshot())
        legend.name = "language-icon-legend"; legend.lifetime = .keepAlways; add(legend)
        app.buttons["language.legend"].tap()
        for (query, id, speech, voice) in [
            ("Русский", "ru", "Распознавание речи поддерживается", "Озвучка"),
            ("Indonesian", "id", "Распознавание речи поддерживается", "Озвучка"),
            ("Балийский", "ban", "Распознавание речи", "Озвучка")
        ] {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText(query)
            let row = app.buttons["language.option." + id]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue((row.value as? String ?? "").contains(speech))
            XCTAssertTrue((row.value as? String ?? "").contains(voice))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "language-capabilities-" + id; shot.lifetime = .keepAlways; add(shot)
            endLanguageSearch(app)
            app.buttons["language.close"].tap()
            app.buttons["language.target"].tap()
        }
        app.buttons["language.close"].tap()
    }

    @MainActor func testAllTransferredVoicesAreReady() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-automaticModelLoad", "NO"]
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        app.launch()
        let settings = app.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 180)); settings.tap()
        let voices = app.buttons["Голоса и образцы"]
        for _ in 0..<4 { if voices.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(voices.waitForExistence(timeout: 10)); voices.tap()
        let coverage = app.staticTexts["voices.coverage"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "label == %@", "Готово языков: 108 из 108"), evaluatedWith: coverage)
        waitForExpectations(timeout: 360)
        XCTAssertFalse(app.buttons["voices.downloadAll"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "all-108-voice-languages-ready"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testOmniVoiceAloneAndWithIndex9() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launchEnvironment = [:]; app.launch() }
        for warm in [false, true] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-automaticModelLoad", warm ? "YES" : "NO", "-translationSource", warm ? "ru" : "ms", "-translationTarget", warm ? "ms" : "en", "-automaticLanguage", "NO", "-selectedTranslationModel", "index-translate-9b-q4km", "-memorySaving", "NO", "-automaticSpeechText", warm ? "YES" : "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
            app.launchEnvironment = ["OT_TTS_MEMORY_TRACE": "1", "OT_MT_MEMORY_TRACE": "1"]
            app.launch()
            XCTAssertTrue(app.segmentedControls.buttons["Текст"].waitForExistence(timeout: 180))
            app.segmentedControls.buttons["Текст"].tap()
            let editor = app.textViews["Текст оригинала"]
            XCTAssertTrue(editor.waitForExistence(timeout: 30)); editor.tap()
            editor.typeText(warm ? "Доброе утро. Спасибо за вашу помощь." : "Selamat pagi! Terima kasih atas bantuan anda.")
            if app.buttons["Скрыть клавиатуру"].exists { app.buttons["Скрыть клавиатуру"].tap() }
            if warm {
                let translate = app.buttons["text.translate"]
                expectation(for: NSPredicate(format: "label == %@ AND enabled == true", "Перевести"), evaluatedWith: translate)
                waitForExpectations(timeout: 180)
                translate.tap()
            } else {
                let start = app.buttons["text.source.playback.startStop"]
                expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
                waitForExpectations(timeout: 180); start.tap()
            }
            XCTAssertTrue(app.staticTexts["Озвучиваю…"].waitForExistence(timeout: 90), "OmniVoice must produce playable audio")
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = warm ? "omnivoice-with-index9" : "omnivoice-alone"; shot.lifetime = .keepAlways; add(shot)
            let prefix = warm ? "text.translation.playback" : "text.source.playback"
            let pause = app.buttons[prefix + ".pauseResume"]
            if pause.exists && pause.isHittable {
                pause.tap()
                XCTAssertEqual(pause.label, "Продолжить озвучку")
                pause.tap()
            }
            let stop = app.buttons[prefix + ".startStop"]
            if stop.exists && stop.label == "Остановить озвучку" { stop.tap() }
        }
    }

    @MainActor func testRoundTwoVoicesDownloadAndNativePlayback() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launchEnvironment = [:]; app.launch() }
        for (code, name, voice, phrase) in [
            ("fa", "Персидский", "vits-piper-fa_IR-amir-medium", "سلام، حال شما چطور است؟"),
            ("tl", "Тагальский", "mms-tts-tgl-onnx", "Kumusta! Magandang umaga."),
            ("hy", "Армянский", "piper-hy_AM-gor-medium", "Բարև ձեզ։ Ինչպե՞ս եք։")
        ] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-automaticModelLoad", "YES", "-translationSource", code, "-translationTarget", "en", "-automaticLanguage", "NO", "-selectedTranslationModel", "index-translate-9b-q4km", "-memorySaving", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
            app.launchEnvironment = ["OT_TTS_MEMORY_TRACE": "1", "OT_MT_MEMORY_TRACE": "1"]
            app.launch()
            let source = app.buttons["language.source"]
            XCTAssertTrue(source.waitForExistence(timeout: 180))
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: source)
            waitForExpectations(timeout: 180)
            source.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText(name)
            let status = app.buttons["language.voice." + code]
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: status)
            waitForExpectations(timeout: 180)
            status.tap()
            let sample = app.buttons["voices.preview." + code + "." + voice]
            XCTAssertTrue(sample.waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["Использовать этот голос"].waitForExistence(timeout: 240))
            sample.tap()
            XCTAssertTrue(app.buttons["Остановить образец"].waitForExistence(timeout: 3))
            sample.tap()
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "new-voice-ready-" + code; shot.lifetime = .keepAlways; add(shot)
            app.buttons["language.close"].tap()
            app.segmentedControls.buttons["Текст"].tap()
            let editor = app.textViews["Текст оригинала"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.tap(); editor.typeText(phrase)
            if app.buttons["Скрыть клавиатуру"].exists { app.buttons["Скрыть клавиатуру"].tap() }
            let start = app.buttons["text.source.playback.startStop"]
            XCTAssertTrue(start.waitForExistence(timeout: 10))
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
            waitForExpectations(timeout: 60)
            start.tap()
            XCTAssertTrue(app.staticTexts["Озвучиваю…"].waitForExistence(timeout: 60), "Actual native synthesis must reach playback")
            let audio = XCTAttachment(screenshot: app.screenshot()); audio.name = "new-voice-native-playback-" + code; audio.lifetime = .keepAlways; add(audio)
            if start.label == "Остановить озвучку" { start.tap() }
        }
    }

    @MainActor func testSpeechExpansionDownloadAndMemoryAdvice() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-automaticModelLoad", "NO"]; app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 120))
        let source = app.buttons["language.source"].value as? String
        let target = app.buttons["language.target"].value as? String
        app.buttons["language.target"].tap()
        let readyVoice = app.buttons["language.voice.en"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: readyVoice)
        waitForExpectations(timeout: 120)
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: search)
        waitForExpectations(timeout: 10)
        search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { search.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Балийский")
        let voice = app.buttons["language.voice.ban"]
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: voice)
        waitForExpectations(timeout: 120)
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "balinese-download-icon"; before.lifetime = .keepAlways; add(before)
        voice.tap()
        let preview = app.buttons["voices.preview.ban.mms-tts-ban-onnx"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15), "Voice icon should navigate to the selected language")
        XCTAssertTrue(preview.isHittable, "Target language should be visible without manual scrolling")
        let downloading = XCTAttachment(screenshot: app.screenshot()); downloading.name = "balinese-voice-download"; downloading.lifetime = .keepAlways; add(downloading)
        // A completed two-file package exposes the selection action. No manual second Download tap.
        XCTAssertTrue(app.buttons["Использовать этот голос"].waitForExistence(timeout: 180))
        preview.tap()
        XCTAssertTrue(app.buttons["Остановить образец"].waitForExistence(timeout: 3))
        preview.tap()
        let ready = XCTAttachment(screenshot: app.screenshot()); ready.name = "balinese-voice-ready"; ready.lifetime = .keepAlways; add(ready)
        // Close the enclosing language sheet; opening voices must not change either language.
        app.buttons["language.close"].tap()
        XCTAssertEqual(app.buttons["language.source"].value as? String, source)
        XCTAssertEqual(app.buttons["language.target"].value as? String, target)
        app.buttons["Модели"].tap()
        for id in ["index-translate-9b-q4km"] {
            let badge = app.descendants(matching: .any)["model.recommended." + id].firstMatch
            for _ in 0..<5 { if badge.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(badge.exists)
        }
        XCTAssertFalse(app.descendants(matching: .any)["model.recommended.qwen35-9b-q4km"].firstMatch.exists)
        let ram = XCTAttachment(screenshot: app.screenshot()); ram.name = "model-ram-recommendations"; ram.lifetime = .keepAlways; add(ram)
        app.buttons["Готово"].tap()
    }

    @MainActor func testExpandedVoicePackageRestoresWithoutRedownload() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-automaticModelLoad", "NO"]; app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 120))
        let source = app.buttons["language.source"].value as? String
        let target = app.buttons["language.target"].value as? String
        app.buttons["language.target"].tap()
        let voice = app.buttons["language.voice.id"]
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == 'Готов'"), evaluatedWith: voice)
        waitForExpectations(timeout: 120)
        voice.tap()
        let sample = app.buttons["voices.preview.id.sherpa-onnx-supertonic-3-tts-int8-2026-05-11"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10)); XCTAssertTrue(sample.isHittable)
        sample.tap()
        XCTAssertTrue(app.buttons["Остановить образец"].waitForExistence(timeout: 3))
        sample.tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "expanded-supertonic-restored"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["language.close"].tap()
        XCTAssertEqual(app.buttons["language.source"].value as? String, source)
        XCTAssertEqual(app.buttons["language.target"].value as? String, target)
    }

    @MainActor func testSelectedDownloadedModelLoadsAtLaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "YES", "-selectedTranslationModel", "qwen35-9b-q4km", "-memorySaving", "NO"] + ["-showTechnicalInfo", "YES"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.buttons["voice.record"].waitForExistence(timeout: 180), "Downloaded selected model should become ready without pressing Prepare")
        XCTAssertFalse(app.buttons["Подготовить перевод"].exists)
        XCTAssertTrue(app.staticTexts["model.current"].label.contains("Qwen"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "automatic-model-ready"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testFavoriteLanguagesPersistAcrossPickersAndRelaunch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["-automaticModelLoad", "NO"]; app.launch()
        XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 120))
        app.buttons["language.target"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Indonesian")
        let star = app.buttons["language.favorite.id"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        let wasFavorite = star.value as? String == "Избранный"
        if !wasFavorite { star.tap() }
        XCTAssertEqual(star.value as? String, "Избранный")
        XCTAssertTrue(app.searchFields.firstMatch.exists, "Star must not select the language or close the picker")
        endLanguageSearch(app)
        app.buttons["language.close"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["language.source"].waitForExistence(timeout: 120))
        app.buttons["language.source"].tap()
        let favorite = app.buttons["language.favorite.id"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5)); XCTAssertEqual(favorite.value as? String, "Избранный")
        XCTAssertTrue(app.staticTexts["Избранные"].exists)
        XCTAssertTrue(app.buttons["language.option.id"].isHittable, "Favorite should be at the top without scrolling")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "language-favorites"; shot.lifetime = .keepAlways; add(shot)
        if !wasFavorite { favorite.tap() }
        app.buttons["language.close"].tap()
    }

    @MainActor func testLanguageSearchAndNewTextDirection() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO"]; app.launch()
        XCTAssertTrue(app.buttons["language.source"].waitForExistence(timeout: 120))
        let savedSource = app.buttons["language.source"].value as? String ?? "ru"
        let savedTarget = app.buttons["language.target"].value as? String ?? "en"
        app.terminate()
        app.launchArguments = ["-automaticModelLoad", "NO", "-selectedTranslationModel", "qwen35-9b-q4km", "-translationSource", "ru", "-translationTarget", "en", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-memorySaving", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch()
        func select(_ side: String, query: String, id: String) {
            let button = app.buttons["language." + side]
            for _ in 0..<6 { if button.isHittable { break }; app.swipeDown() }
            button.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText(query)
            let option = app.buttons["language.option." + id]
            XCTAssertTrue(option.waitForExistence(timeout: 5)); XCTAssertTrue(option.isEnabled)
            option.tap()
            XCTAssertEqual(app.buttons["language." + side].value as? String, id)
        }
        defer {
            if app.searchFields.firstMatch.exists { endLanguageSearch(app) }
            if app.buttons["language.close"].exists { app.buttons["language.close"].tap() }
            if app.buttons["Отменить"].exists { app.buttons["Отменить"].tap() }
            if app.segmentedControls.buttons["Текст"].exists { app.segmentedControls.buttons["Текст"].tap() }
            select("source", query: savedSource, id: savedSource)
            select("target", query: savedTarget, id: savedTarget)
            app.terminate(); app.launchArguments = []; app.launch()
        }
        XCTAssertTrue(app.buttons["Модели"].waitForExistence(timeout: 120))
        app.buttons["Модели"].tap()
        let selected = app.buttons["model.select.qwen35-9b-q4km"]
        for _ in 0..<6 { if selected.exists { break }; app.swipeUp() }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: selected)
        waitForExpectations(timeout: 180)
        app.buttons["Готово"].tap()
        app.segmentedControls.buttons["Текст"].tap()
        select("target", query: "Балий", id: "ban")
        XCTAssertTrue(app.staticTexts["Для этого языка пока доступен перевод без озвучки."].exists)
        select("source", query: "Indonesian", id: "id")
        select("target", query: "Русский", id: "ru")
        app.buttons["language.target"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("несуществующийязык")
        XCTAssertTrue(app.staticTexts["Язык не найден"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "language-search-empty"; shot.lifetime = .keepAlways; add(shot)
        endLanguageSearch(app)
        app.buttons["language.close"].tap()
        let editor = app.textViews["Текст оригинала"]
        for _ in 0..<6 { if editor.isHittable { break }; app.swipeUp() }
        editor.tap(); editor.typeText("Di mana apotek terdekat?")
        let prepare = app.buttons["Подготовить перевод"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 180)); prepare.tap()
        let translate = app.buttons["Перевести"]
        XCTAssertTrue(translate.waitForExistence(timeout: 180)); translate.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["text.copy.target"])
        waitForExpectations(timeout: 90)
        XCTAssertFalse(app.staticTexts["text.translation.text"].label.isEmpty)
        let result = XCTAttachment(string: app.staticTexts["text.translation.text"].label); result.name = "indonesian-russian"; result.lifetime = .keepAlways; add(result)
        let translated = XCTAttachment(screenshot: app.screenshot()); translated.name = "language-indonesian-result"; translated.lifetime = .keepAlways; add(translated)
        // Verify selecting the same language swaps the pair, and the reverse control still works.
        select("source", query: "Русский", id: "ru")
        XCTAssertEqual(app.buttons["language.target"].value as? String, "id")
        app.buttons["Поменять языки местами"].tap()
        XCTAssertEqual(app.buttons["language.source"].value as? String, "id")
        select("source", query: "Балий", id: "ban")
        app.segmentedControls.buttons["Голос"].tap()
        XCTAssertTrue(app.staticTexts["Голосовой ввод этого языка пока недоступен. Используйте текстовый режим."].exists)
        app.segmentedControls.buttons["Текст"].tap()
    }

    /// Same fixtures, A/B/B/A order. MT timing comes from the backend trace, not UI waits.
    @MainActor func testIndexQwenMatchedDeviceBenchmark() throws {
        guard ProcessInfo.processInfo.environment["OFFLINE_RUN_LONG_BENCHMARK"] == "1" else { throw XCTSkip("Long stress tests are opt-in; user requested no more large runs.") }
        try runMatchedBenchmark(includeLong: true)
    }
    @MainActor func testIndexQwenMatchedWarmComparison() throws {
        try runMatchedBenchmark(includeLong: false)
    }
    @MainActor private func runMatchedBenchmark(includeLong: Bool) throws {
        continueAfterFailure = false
        executionTimeAllowance = 2400
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        defer { app.terminate(); app.launchArguments = []; app.launchEnvironment = [:]; app.launch() }
        let fixtures = [
            "Где находится ближайшая аптека?",
            "Где находится ближайшая аптека?",
            "Не отменяйте бронь. Измените дату приезда с 15 на 16 октября. Завтрак включён, а ужин оплачивается отдельно.",
            "Здравствуйте. Мы забронировали номер на две ночи и уже оплатили проживание. В номере не работает кондиционер, а из окна слышен сильный шум. Можно переселить нас в тихий номер за ту же цену? Если свободных номеров нет, пожалуйста, пришлите мастера сегодня, а не завтра."
        ]
        let longFixtures = [
            """
            Здравствуйте. Я пишу, чтобы подробно описать нашу поездку и уточнить условия бронирования. Мы приезжаем 15 октября вечером и уезжаем 22 октября утром. С нами будут двое взрослых и ребёнок семи лет. Нам нужен один тихий номер с двумя отдельными кроватями и дополнительным спальным местом. Номер для курящих нам не подходит. Пожалуйста, не отменяйте существующую бронь: сначала сообщите, какие изменения возможны и сколько они будут стоить.

            Наш самолёт должен приземлиться в 19:40, но задержка рейса может составить до двух часов. На паспортный контроль и получение багажа мы закладываем ещё девяносто минут. Поэтому в гостиницу мы, возможно, приедем после полуночи. Подтвердите, что позднее заселение разрешено и стойка регистрации будет работать. Если нужен специальный код для входа, пришлите его заранее вместе с адресом и фотографией главного входа. У нас не всегда будет доступ к интернету.

            Предоплата за проживание уже внесена: с карты списали 18 500 рублей. В подтверждении написано, что оставшаяся сумма составляет 7 200 рублей, однако в последнем письме указаны 8 700 рублей. Объясните, пожалуйста, откуда появилась разница. Если это туристический сбор, укажите его отдельно и уточните, берут ли его с детей. Я не согласен на дополнительные услуги без предварительного обсуждения. Чек и подтверждение оплаты у меня сохранены.

            У ребёнка аллергия на арахис и кешью. Это не просто предпочтение в еде: даже небольшое количество орехов может вызвать реакцию. Нас интересует не только состав блюда, но и возможность перекрёстного загрязнения на кухне. Можно ли приготовить завтрак отдельно и использовать чистую посуду? Если вы не можете этого гарантировать, честно сообщите об этом. Мы выберем другой вариант питания, и это не будет основанием для отмены номера.
            Последний пункт: сохраните код проверки ZX-2048.
            """,
            """
            Здравствуйте. Я пишу, чтобы подробно описать нашу поездку и уточнить условия бронирования. Мы приезжаем 15 октября вечером и уезжаем 22 октября утром. С нами будут двое взрослых и ребёнок семи лет. Нам нужен один тихий номер с двумя отдельными кроватями и дополнительным спальным местом. Номер для курящих нам не подходит. Пожалуйста, не отменяйте существующую бронь: сначала сообщите, какие изменения возможны и сколько они будут стоить.

            Наш самолёт должен приземлиться в 19:40, но задержка рейса может составить до двух часов. На паспортный контроль и получение багажа мы закладываем ещё девяносто минут. Поэтому в гостиницу мы, возможно, приедем после полуночи. Подтвердите, что позднее заселение разрешено и стойка регистрации будет работать. Если нужен специальный код для входа, пришлите его заранее вместе с адресом и фотографией главного входа. У нас не всегда будет доступ к интернету.

            Предоплата за проживание уже внесена: с карты списали 18 500 рублей. В подтверждении написано, что оставшаяся сумма составляет 7 200 рублей, однако в последнем письме указаны 8 700 рублей. Объясните, пожалуйста, откуда появилась разница. Если это туристический сбор, укажите его отдельно и уточните, берут ли его с детей. Я не согласен на дополнительные услуги без предварительного обсуждения. Чек и подтверждение оплаты у меня сохранены.

            У ребёнка аллергия на арахис и кешью. Это не просто предпочтение в еде: даже небольшое количество орехов может вызвать реакцию. Нас интересует не только состав блюда, но и возможность перекрёстного загрязнения на кухне. Можно ли приготовить завтрак отдельно и использовать чистую посуду? Если вы не можете этого гарантировать, честно сообщите об этом. Мы выберем другой вариант питания, и это не будет основанием для отмены номера.

            В стоимость нашего тарифа включён завтрак, но не включены обед и ужин. Мы хотели бы узнать, во сколько открывается ресторан и можно ли взять завтрак с собой в день ранней экскурсии. Экскурсия начинается в 06:30, а автобус забирает нас в 05:50. Нам подойдёт простой набор: вода, хлеб, сыр и фрукты без орехов. Не добавляйте сладкие батончики, состав которых неизвестен. Если такая услуга платная, сначала назовите цену за каждого человека.

            В описании гостиницы говорится, что трансфер из аэропорта бесплатный, но только при бронировании от семи ночей. У нас именно семь ночей, поэтому прошу подтвердить, что это условие действует. В машине необходимо детское кресло, подходящее для ребёнка ростом 125 сантиметров. Обычный ремень без дополнительного удерживающего устройства нас не устраивает. У водителя должна быть табличка с фамилией Иванов. Пожалуйста, сообщите точное место встречи после выхода из зоны прилёта.

            Если трансфер опоздает, мы подождём не больше тридцати минут, после чего возьмём официальное такси. Можно ли будет компенсировать его стоимость, если задержка произошла по вашей вине? Я понимаю, что дорожные пробки предсказать трудно, поэтому заранее прошу дать номер диспетчера. Мы не будем садиться в машину человека, который не сможет назвать номер нашего бронирования. Все расчёты за дорогу должны быть понятными до начала поездки.

            Нам важна тишина ночью, поэтому номер рядом с лифтом, баром или техническим помещением не подойдёт. Вид на море приятен, но не является обязательным. Гораздо важнее исправный кондиционер, горячая вода и возможность плотно закрыть окно. Если на территории сейчас идёт ремонт, укажите часы шумных работ. Мы готовы рассмотреть другой корпус за ту же цену. Доплачивать за устранение недостатков, о которых заранее не сообщалось, мы не планируем.

            На второй день поездки мы собираемся арендовать автомобиль. Нужна машина с автоматической коробкой передач, страховкой и понятным размером залога. Объясните разницу между полной страховкой и базовым покрытием: какие повреждения оплачиваются отдельно и есть ли франшиза? Особенно интересуют колёса, стёкла и днище. При получении машины мы хотим вместе с сотрудником осмотреть кузов и записать все старые царапины в акт, чтобы потом не возникло спора.

            Водительское удостоверение и международное разрешение у нас есть. Мы не хотим оставлять оригинал паспорта в качестве залога. Можно предъявить его для проверки и предоставить копию, но документ должен остаться у владельца. Оплата возможна картой или наличными после подписания договора. Если карточный платёж требует комиссии, её нужно указать заранее. Пожалуйста, не меняйте валюту платежа без нашего согласия и выдайте документ с окончательной суммой.

            На экскурсию к водопаду мы хотели бы поехать 18 октября. Подскажите, насколько сложна тропа, есть ли опасные участки и можно ли пройти её с ребёнком. Мы не уверены, что готовы к длительному подъёму по скользким камням. Если в день экскурсии будет сильный дождь, предпочтём перенос или возврат денег. Обычный небольшой дождь нас не пугает. Решение должно зависеть от безопасности маршрута, а не только от желания организатора сохранить расписание.

            Нас интересует также поездка на лодке, но только при спокойном море. У каждого пассажира должен быть исправный спасательный жилет подходящего размера. Ребёнку нельзя выдавать взрослый жилет, который соскальзывает через голову. Мы готовы отказаться от поездки, если капитан считает условия опасными. Перед выходом уточните время возвращения, наличие питьевой воды и возможность укрыться от солнца. Стоимость снаряжения должна входить в согласованную цену.

            Во время прогулки мы потеряли небольшой синий рюкзак. Внутри были зарядное устройство, детская кофта и блокнот, но не было паспорта и банковских карт. Последний раз рюкзак видели в кафе возле северного входа в парк около 16:20. Если кто-нибудь его нашёл, попросите оставить вещь у администратора. Мы можем подробно описать содержимое и показать фотографию рюкзака. Вознаграждение за возврат возможно, однако переводить деньги неизвестному человеку заранее мы не будем.

            В ресторане вчера возникла ошибка в счёте. Мы заказали два супа по 180, одно основное блюдо за 320 и три бутылки воды по 40. Общая сумма без сбора должна составлять 800. В счёте указано 980, причём отдельная строка обслуживания отсутствует. Пожалуйста, проверьте позиции: возможно, нам добавили чужой заказ. Мы не отказываемся платить за то, что действительно получили, но хотим сначала разобраться в расчёте и получить исправленный чек.

            Если во время поездки понадобится медицинская помощь, подскажите ближайшую клинику, где принимают иностранцев. У нас есть туристическая страховка, и перед обращением мы должны связаться с сервисной компанией. При неотложной ситуации ожидать ответа страховой не будем. Нужны адрес, телефон и примерное время в пути от гостиницы. Мы не просим персонал ставить диагноз или назначать лекарства: требуется только помощь с организацией обращения к специалисту.

            В день отъезда нам нужно освободить номер до 11:00, а самолёт вылетает только в 20:15. Можно ли оставить чемоданы в закрытой комнате хранения и забрать их около 16:30? Нам также пригодится место, где можно переодеться перед дорогой. Если поздний выезд доступен за дополнительную плату, укажите точную стоимость и время, до которого разрешено пользоваться номером. Не продлевайте проживание автоматически: окончательное решение мы сообщим накануне.

            Пожалуйста, ответьте на вопросы по пунктам и не заменяйте конкретные условия общей рекламой гостиницы. Если какая-то услуга пока не подтверждена, так и напишите. Нас устроит честный ответ с вариантами решения. Особенно важно сохранить даты, суммы, количество гостей и сведения об аллергии без изменений. Спасибо за помощь в подготовке поездки. Мы рассчитываем заранее договориться о деталях, чтобы на месте спокойно отдыхать и не тратить время на выяснение недоразумений.
            Последний пункт: сохраните код проверки ZX-8192.
            """
        ]
        let order = ["index-translate-9b-q4km", "qwen35-9b-q4km", "qwen35-9b-q4km", "index-translate-9b-q4km"] + (includeLong ? ["index-translate-9b-q4km", "qwen35-9b-q4km"] : [])
        for (block, id) in order.enumerated() {
            app.terminate()
            app.launchEnvironment = ["OT_MT_MEMORY_TRACE": "1"]
            app.launchArguments = ["-automaticModelLoad", "NO", "-selectedTranslationModel", id, "-translationSource", "ru", "-translationTarget", "en", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-memorySaving", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
            app.launch()
            XCTAssertTrue(app.buttons["Модели"].waitForExistence(timeout: 120))
            app.buttons["Модели"].tap()
            let selected = app.buttons["model.select." + id]
            for _ in 0..<6 { if selected.exists { break }; app.swipeUp() }
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: selected)
            waitForExpectations(timeout: 180) // All package verification/voice preparation has finished.
            XCTAssertEqual(selected.value as? String, "Выбрана")
            app.buttons["Готово"].tap()
            XCTAssertTrue(app.segmentedControls.buttons["Текст"].waitForExistence(timeout: 120))
            app.segmentedControls.buttons["Текст"].tap()
            for (number, fixture) in (block < 4 ? fixtures : longFixtures).enumerated() {
                let clear = app.buttons["text.clear.source"]
                if number > 0 {
                    for _ in 0..<5 { if clear.isHittable { break }; app.swipeDown() }
                    clear.tap()
                }
                let editor = app.textViews["Текст оригинала"]
                for _ in 0..<5 { if editor.isHittable { break }; app.swipeUp() }
                editor.tap(); editor.typeText(fixture)
                XCTAssertEqual(editor.value as? String, fixture)
                let prepare = app.buttons["Подготовить перевод"]
                if number == 0 {
                    XCTAssertTrue(prepare.waitForExistence(timeout: 180))
                    prepare.tap()
                }
                let translate = app.buttons["Перевести"]
                XCTAssertTrue(translate.waitForExistence(timeout: 180))
                expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: translate)
                waitForExpectations(timeout: 180)
                let started = Date().timeIntervalSince1970
                translate.tap()
                expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["text.copy.target"])
                waitForExpectations(timeout: 600)
                let result = app.staticTexts["text.translation.text"]
                XCTAssertFalse(result.label.isEmpty)
                let data = try JSONSerialization.data(withJSONObject: ["block": block, "case": number, "model": id, "source": fixture, "translation": result.label, "startedAt": started, "finishedAt": Date().timeIntervalSince1970, "endMarkerPresent": block < 4 || result.label.contains(number == 0 ? "ZX-2048" : "ZX-8192")], options: [.sortedKeys, .prettyPrinted])
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "matched-\(block)-\(number)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    @MainActor func testLargeTextProgressAndCancellation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "ru", "-translationTarget", "en", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-memorySaving", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.buttons["Модели"].waitForExistence(timeout: 120))
        app.buttons["Модели"].tap()
        let selected = app.buttons["model.select.index-translate-9b-q4km"]
        for _ in 0..<6 { if selected.exists { break }; app.swipeUp() }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: selected)
        waitForExpectations(timeout: 180)
        app.buttons["Готово"].tap()
        app.segmentedControls.buttons["Текст"].tap()
        let fixture = String(String(repeating: "Здравствуйте. Мы забронировали тихий номер на две ночи. Не отменяйте бронь, только измените дату приезда с 15 на 16 октября. Завтрак включён в стоимость, но ужин оплачивается отдельно. ", count: 6).prefix(1000))
        XCTAssertGreaterThanOrEqual(fixture.count, 1000)
        let editor = app.textViews["Текст оригинала"]
        for _ in 0..<5 { if editor.isHittable { break }; app.swipeUp() }
        editor.tap(); editor.typeText(fixture)
        XCTAssertEqual(editor.value as? String, fixture)
        let prepare = app.buttons["Подготовить перевод"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 180)); prepare.tap()
        let translate = app.buttons["Перевести"]
        XCTAssertTrue(translate.waitForExistence(timeout: 180)); translate.tap()
        let progress = app.descendants(matching: .any).matching(identifier: "translation.progress").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "translation-progress"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Отменить"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: progress)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(translate.waitForExistence(timeout: 30))
        let clear = app.buttons["text.clear.source"]
        for _ in 0..<5 { if clear.isHittable { break }; app.swipeDown() }
        clear.tap(); editor.tap(); editor.typeText("Где находится ближайшая аптека?")
        translate.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["text.copy.target"])
        waitForExpectations(timeout: 90)
        XCTAssertFalse(progress.exists)
        XCTAssertFalse(app.staticTexts["text.translation.text"].label.isEmpty)
    }

    @MainActor func testModelAdviceDoesNotChangeSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-automaticModelLoad", "NO"] + ["-showTechnicalInfo", "YES"]; app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.buttons["Модели"].waitForExistence(timeout: 120))
        let current = app.staticTexts["model.current"].label
        app.buttons["Модели"].tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        let indexBadge = app.descendants(matching: .any)["model.recommended.index-translate-9b-q4km"].firstMatch
        reveal(indexBadge)
        XCTAssertTrue(indexBadge.exists)
        let qwen = app.buttons["model.info.qwen35-9b-q4km"]
        reveal(qwen)
        XCTAssertFalse(app.descendants(matching: .any)["model.recommended.qwen35-9b-q4km"].firstMatch.exists)
        qwen.tap()
        XCTAssertTrue(app.staticTexts["Заявлено авторами: 201 язык и диалект"].waitForExistence(timeout: 5))
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "model-advice-qwen"; detail.lifetime = .keepAlways; add(detail)
        app.buttons["model.info.close"].tap()
        XCTAssertFalse(app.buttons["model.select.mil-mmt46-12b-v1-q4km"].exists)
        XCTAssertFalse(app.buttons["model.info.mil-mmt46-12b-v1-q4km"].exists)
        let menu = XCTAttachment(screenshot: app.screenshot()); menu.name = "model-advice-list"; menu.lifetime = .keepAlways; add(menu)
        app.buttons["Готово"].tap()
        XCTAssertEqual(app.staticTexts["model.current"].label, current, "Reading advice must not select or unload another model")
    }

    @MainActor func testVoiceRecordingPauseAndSpeedDrag() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-recordingMode", "toggle", "-recordingSilenceSeconds", "1", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-automaticSpeechVoice", "NO"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        let prepare = app.buttons["Подготовить перевод"]
        let record = app.buttons["voice.record"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 30) || record.exists)
        if prepare.exists { prepare.tap() }
        XCTAssertTrue(record.waitForExistence(timeout: 180))
        record.tap()
        let pause = app.buttons["voice.pauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        pause.tap(); XCTAssertEqual(pause.label, "Продолжить запись")
        let timer = app.staticTexts["voice.recording.time"]
        let frozen = timer.label
        let delay = expectation(description: "Stay paused longer than silence timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { delay.fulfill() }
        wait(for: [delay], timeout: 5)
        XCTAssertEqual(timer.label, frozen)
        XCTAssertEqual(record.label, "Завершить запись")
        XCTAssertEqual(record.frame.midY, pause.frame.midY, accuracy: 4)
        XCTAssertGreaterThan(pause.frame.minX, record.frame.maxX)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "recording-paused-bottom-controls"; screenshot.lifetime = .keepAlways; add(screenshot)
        pause.tap(); XCTAssertEqual(pause.label, "Приостановить запись")
        pause.tap(); record.tap()
        expectation(for: NSPredicate(format: "label == %@", "Начать запись"), evaluatedWith: record)
        waitForExpectations(timeout: 120)
        let textTab = app.segmentedControls.buttons["Текст"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: textTab)
        waitForExpectations(timeout: 120)
        textTab.tap()
        let speed = app.buttons["text.source.playback.speed"]
        for _ in 0..<5 { if speed.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(speed.value as? String, "×1")
        let origin = speed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.6, thenDragTo: origin.withOffset(CGVector(dx: -168, dy: 0)))
        XCTAssertEqual(speed.value as? String, "×2", "All four speeds must be reachable toward the free left side")
        origin.press(forDuration: 0.6, thenDragTo: origin.withOffset(CGVector(dx: 56, dy: 0)))
        XCTAssertEqual(speed.value as? String, "×1,5")
        speed.tap(); XCTAssertEqual(speed.value as? String, "×2")
    }

    @MainActor func testPlaybackSpeedMenuPauseAndRecordingLimit() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-automaticSpeechText", "NO", "-automaticLanguage", "NO"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.buttons["Настройки"].waitForExistence(timeout: 30))
        app.buttons["Настройки"].tap()
        let limit = app.steppers["recording.limit.stepper"]
        XCTAssertTrue(limit.waitForExistence(timeout: 10))
        let limitValue = app.descendants(matching: .any).matching(identifier: "recording.limit.value").firstMatch
        func minutes() -> Int { Int((limitValue.value as? String ?? "").split(separator: " ").first ?? "") ?? 0 }
        let initial = minutes()
        XCTAssertTrue((1...30).contains(initial))
        let changed = initial == 30 ? initial - 1 : initial + 1
        limit.buttons.element(boundBy: initial == 30 ? 0 : 1).tap()
        XCTAssertEqual(minutes(), changed)
        app.buttons["Готово"].tap()
        app.buttons["Настройки"].tap()
        XCTAssertEqual(minutes(), changed)
        for _ in 0..<30 {
            let current = minutes()
            if current == 10 { break }
            limit.buttons.element(boundBy: current > 10 ? 0 : 1).tap()
        }
        XCTAssertEqual(minutes(), 10)
        app.buttons["Готово"].tap()
        app.segmentedControls.buttons["Текст"].tap()
        app.buttons["Выбрать исходный язык"].tap(); app.buttons["Русский"].tap()
        app.buttons["Выбрать язык перевода"].tap(); app.buttons["Английский"].tap()
        let action = app.buttons["text.translate"]
        expectation(for: NSPredicate(format: "label == %@ OR label == %@", "Подготовить перевод", "Перевести"), evaluatedWith: action)
        waitForExpectations(timeout: 180)
        if action.label == "Подготовить перевод" { action.tap() }
        expectation(for: NSPredicate(format: "label == %@", "Перевести"), evaluatedWith: action)
        waitForExpectations(timeout: 180)
        func reveal(_ element: XCUIElement) {
            for _ in 0..<5 { if element.isHittable { return }; app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        let speed = app.buttons["text.source.playback.speed"]
        reveal(speed)
        XCTAssertEqual(speed.value as? String, "×1")
        for value in ["×1,25", "×1,5", "×2", "×1"] {
            speed.tap(); XCTAssertEqual(speed.value as? String, value)
        }
        speed.press(forDuration: 0.7)
        let first = app.buttons["text.source.playback.speed.option.1.0"]
        let fast = app.buttons["text.source.playback.speed.option.1.5"]
        XCTAssertTrue(fast.waitForExistence(timeout: 5))
        XCTAssertEqual(speed.value as? String, "×1", "Holding must not also advance the speed")
        XCTAssertEqual(first.frame.midY, fast.frame.midY, accuracy: 2)
        XCTAssertGreaterThan(first.frame.minX, fast.frame.minX, "Faster options must appear to the left")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "horizontal-speed-menu"; shot.lifetime = .keepAlways; add(shot)
        fast.tap(); XCTAssertEqual(speed.value as? String, "×1,5")
        let editor = app.textViews["Текст оригинала"]
        reveal(editor); editor.tap()
        editor.typeText(String(repeating: "Здравствуйте. Мы хотели бы заказать ужин и узнать, во сколько завтра открывается ресторан. ", count: 5))
        app.buttons["Скрыть клавиатуру"].tap()
        if !speed.isHittable { app.swipeDown() }; reveal(speed)
        let startStop = app.buttons["text.source.playback.startStop"]
        startStop.tap()
        let pause = app.buttons["text.source.playback.pauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 30))
        pause.tap(); XCTAssertEqual(pause.label, "Продолжить озвучку")
        speed.tap(); XCTAssertEqual(speed.value as? String, "×2")
        let paused = XCTAttachment(screenshot: app.screenshot()); paused.name = "paused-playback"; paused.lifetime = .keepAlways; add(paused)
        pause.tap(); XCTAssertEqual(pause.label, "Приостановить озвучку")
        pause.tap(); startStop.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pause)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(startStop.label, "Озвучить оригинал")
        app.buttons["text.clear.source"].tap()
    }

    @MainActor func testRepeatedCopyReplacesClipboardAgain() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-automaticSpeechText", "NO", "-automaticLanguage", "NO"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.segmentedControls.buttons["Текст"].waitForExistence(timeout: 30))
        app.segmentedControls.buttons["Текст"].tap()
        app.buttons["Выбрать исходный язык"].tap(); app.buttons["Русский"].tap()
        app.buttons["Выбрать язык перевода"].tap(); app.buttons["Английский"].tap()
        let action = app.buttons["text.translate"]
        expectation(for: NSPredicate(format: "label == %@ OR label == %@", "Подготовить перевод", "Перевести"), evaluatedWith: action)
        waitForExpectations(timeout: 180)
        if action.label == "Подготовить перевод" { action.tap() }
        expectation(for: NSPredicate(format: "label == %@", "Перевести"), evaluatedWith: action)
        waitForExpectations(timeout: 180)
        func reveal(_ element: XCUIElement) {
            for _ in 0..<5 { if element.isHittable { return }; app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        let editor = app.textViews["Текст оригинала"]
        reveal(editor); editor.tap(); editor.typeText("Где находится вокзал?")
        action.tap()
        let target = app.buttons["text.copy.target"], source = app.buttons["text.copy.source"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: target)
        waitForExpectations(timeout: 120)
        let translated = app.staticTexts["text.translation.text"].label
        XCTAssertFalse(translated.isEmpty)
        reveal(target); target.tap()
        // The other field changes the clipboard; tapping the same target again must restore it.
        if !source.isHittable { app.swipeDown() }; reveal(source); source.tap()
        reveal(target); target.tap(); XCTAssertTrue(target.isEnabled)
        app.buttons["text.clear.target"].tap()
        if !editor.isHittable { app.swipeDown() }; reveal(editor)
        editor.tap(); editor.press(forDuration: 1.2)
        let paste = app.menuItems.matching(NSPredicate(format: "label == 'Paste' OR label == 'Вставить'")).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
        XCTAssertEqual(editor.value as? String, translated)
        app.buttons["Скрыть клавиатуру"].tap()
        app.buttons["text.clear.source"].tap()
    }

    @MainActor func testTransferredCandidateModelsAreInstalled() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Модели"].waitForExistence(timeout: 30))
        app.buttons["Модели"].tap()
        let index = app.buttons["model.select.index-translate-9b-q4km"]
        for _ in 0..<5 { if index.exists && index.isHittable { break }; app.swipeUp() }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: index)
        waitForExpectations(timeout: 180)
        index.tap()
        expectation(for: NSPredicate(format: "value == %@", "Выбрана"), evaluatedWith: index)
        waitForExpectations(timeout: 15)
        for id in ["qwen35-9b-q4km", "mil-mmt46-4b-v1-q4km"] {
            let installed = app.descendants(matching: .any).matching(identifier: "model.installed." + id).firstMatch
            for _ in 0..<16 { if installed.exists && installed.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(installed.exists)
            XCTAssertFalse(app.buttons["model.download." + id].exists)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "installed-" + id; shot.lifetime = .keepAlways; add(shot)
        }
        app.buttons["Готово"].tap()
        app.terminate(); app.launch()
        let current = app.staticTexts["model.current"]
        XCTAssertTrue(current.waitForExistence(timeout: 30))
        XCTAssertTrue(current.label.contains("Index-Translate 9B"))
    }

    @MainActor func testTranslationModelSelectionPersistsWithoutLoadingWeights() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Модели"].waitForExistence(timeout: 120))
        app.buttons["Модели"].tap()
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'model.select.' AND value == 'Выбрана'")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 30))
        let originalID = selected.identifier
        func reveal(_ element: XCUIElement, upward: Bool = true) {
            for _ in 0..<14 {
                if element.exists && element.isHittable { return }
                if upward { app.swipeUp() } else { app.swipeDown() }
            }
            XCTAssertTrue(element.isHittable)
        }
        defer {
            app.terminate(); app.launch()
            if app.buttons["Модели"].waitForExistence(timeout: 30) {
                app.buttons["Модели"].tap()
                let original = app.buttons[originalID]
                reveal(original)
                expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: original)
                waitForExpectations(timeout: 180)
                original.tap()
                expectation(for: NSPredicate(format: "value == %@", "Выбрана"), evaluatedWith: original)
                waitForExpectations(timeout: 15)
                app.buttons["Готово"].tap()
            }
        }
        for id in ["qwen35-9b-q4km", "mil-mmt46-4b-v1-q4km"] {
            let choice = app.buttons["model.select." + id]
            reveal(choice)
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: choice)
            waitForExpectations(timeout: 30)
            choice.tap()
            expectation(for: NSPredicate(format: "value == %@", "Выбрана"), evaluatedWith: choice)
            waitForExpectations(timeout: 15)
            let package = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["model.download." + id, "model.installed." + id])).firstMatch
            reveal(package)
            XCTAssertTrue(package.exists, "Each candidate needs its own downloadable or already installed package")
            app.buttons["Готово"].tap()
            app.terminate(); app.launch()
            XCTAssertTrue(app.buttons["Модели"].waitForExistence(timeout: 30))
            app.buttons["Модели"].tap()
            reveal(choice)
            XCTAssertEqual(choice.value as? String, "Выбрана")
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "candidate-" + id; shot.lifetime = .keepAlways; add(shot)
        }
    }

    @MainActor func testIndex9ShortProbeAndSwitchBack() throws {
        try runIndex9Probe(full: false)
    }

    @MainActor func testIndex9OnDeviceAndSwitchBackWithoutDeletingModels() throws {
        try runIndex9Probe(full: true)
    }

    @MainActor func testIndex9WarmTranslationsWithSpeech() throws {
        try runIndex9Probe(full: false, warm: true)
    }

    @MainActor private func runIndex9Probe(full: Bool, warm: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OT_MT_MEMORY_TRACE"] = "1"
        app.launchArguments = ["-automaticModelLoad", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-automaticSpeechText", warm ? "YES" : "NO", "-memorySaving", "NO"] + ["-showTechnicalInfo", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Модели"].waitForExistence(timeout: 120))
        app.buttons["Модели"].tap()
        let index = app.buttons["model.select.index-translate-9b-q4km"]
        for _ in 0..<4 { if index.isHittable { break }; app.swipeUp() }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: index)
        waitForExpectations(timeout: 120)
        index.tap()
        expectation(for: NSPredicate(format: "value == %@", "Выбрана"), evaluatedWith: index)
        waitForExpectations(timeout: 10)
        app.buttons["Готово"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["model.current"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.staticTexts["model.current"].label.contains("Index-Translate 9B"))
        app.segmentedControls.buttons["Текст"].tap()
        app.buttons["Выбрать исходный язык"].tap(); app.buttons["Русский"].tap()
        let automaticLanguage = app.switches["Автоопределение языка"]
        let restoreAutomatic = warm && automaticLanguage.value as? String == "1"
        if restoreAutomatic { automaticLanguage.tap() }
        let fixtures: [(String, String)] = [
            ("Английский", "У меня аллергия на арахис. В этом блюде есть арахис?"),
            ("Тайский", "Не отменяйте бронь. Измените дату с 15 на 16 октября."),
            ("Испанский", "Мне нужен билет в одну сторону, не туда-обратно."),
            ("Немецкий", "Я потерял паспорт, а не билет."),
            ("Французский", "Я заплатил 500, вы вернули 50. Сдача должна быть 150."),
            ("Турецкий", "У меня аллергия на арахис. В этом блюде есть арахис?"),
            ("Английский", String(repeating: "Здравствуйте. Я забронировал номер на два дня. Не отменяйте бронь, только измените дату приезда с 15 на 16 октября. Завтрак включён в стоимость, но ужин не включён. ", count: 8))
        ]
        let cases = warm ? [fixtures[0], ("Английский", fixtures[1].1)] : full ? fixtures : Array(fixtures.prefix(1))
        for (number, fixture) in cases.enumerated() {
            app.buttons["Выбрать язык перевода"].tap(); app.buttons[fixture.0].tap()
            let editor = app.textViews["Текст оригинала"]
            editor.tap()
            if number > 0 { editor.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
            editor.typeText(fixture.1)
            XCTAssertEqual(editor.value as? String, fixture.1)
            app.swipeDown()
            if app.buttons["Подготовить перевод"].exists { app.buttons["Подготовить перевод"].tap() }
            let translate = app.buttons["Перевести"]
            XCTAssertTrue(translate.waitForExistence(timeout: 120))
            translate.tap()
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Скопировать перевод"])
            waitForExpectations(timeout: warm ? 90 : 240)
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: translate)
            waitForExpectations(timeout: 120)
            let text = XCTAttachment(string: app.debugDescription); text.name = "Index9 result \(number) \(fixture.0)"; text.lifetime = .keepAlways; add(text)
        }
        if warm {
            if restoreAutomatic { automaticLanguage.tap() }
            app.terminate(); app.launchEnvironment = [:]; app.launchArguments = []; app.launch()
            XCTAssertTrue(app.staticTexts["model.current"].waitForExistence(timeout: 120))
            XCTAssertTrue(app.staticTexts["model.current"].label.contains("Index-Translate 9B"))
            return
        }
        app.buttons["Модели"].tap()
        let gemma = app.buttons["model.select.opus-mt-big-en-zle-int8"]
        for _ in 0..<4 { if gemma.isHittable { break }; app.swipeUp() }
        gemma.tap()
        expectation(for: NSPredicate(format: "value == %@", "Выбрана"), evaluatedWith: gemma)
        waitForExpectations(timeout: 10)
        app.buttons["Готово"].tap()
        XCTAssertTrue(app.staticTexts["model.current"].label.contains("OPUS Big"))
        app.terminate()
        app.launchEnvironment = [:]; app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["model.current"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.staticTexts["model.current"].label.contains("OPUS Big"))
    }

    @MainActor func testHistoryRecordingSettingsPersistAndClearCanBeCancelled() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Настройки"].waitForExistence(timeout: 30))
        app.buttons["Настройки"].tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<5 { if element.isHittable { return }; app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        func flip(_ element: XCUIElement) {
            let before = element.value as? String
            // SwiftUI exposes the entire labelled row as a switch; press its actual thumb.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            expectation(for: NSPredicate(format: "value != %@", before ?? ""), evaluatedWith: element)
            waitForExpectations(timeout: 5)
        }
        let text = app.switches["history.recordText"], audio = app.switches["history.recordAudio"]
        reveal(text); let oldText = text.value as? String; flip(text)
        reveal(audio); let oldAudio = audio.value as? String; flip(audio)
        app.buttons["Готово"].tap(); app.buttons["Настройки"].tap()
        reveal(text); XCTAssertNotEqual(text.value as? String, oldText); flip(text)
        reveal(audio); XCTAssertNotEqual(audio.value as? String, oldAudio); flip(audio)
        let clear = app.buttons["history.clear"]; reveal(clear); clear.tap()
        XCTAssertTrue(app.buttons["Удалить весь текст и аудио"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Clear history confirmation"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Отмена"].tap() // Never delete the user's history in a device test.
        XCTAssertTrue(clear.exists)
        app.buttons["Готово"].tap()
    }

    // Completion is not a pronunciation assertion: inspect the captured text/audio separately.
    @MainActor func testCaptureRussianThaiGreetingForQualityReview() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.segmentedControls.buttons["Текст"].waitForExistence(timeout: 30))
        app.segmentedControls.buttons["Текст"].tap()
        app.buttons["Выбрать исходный язык"].tap(); app.buttons["Русский"].tap()
        app.buttons["Выбрать язык перевода"].tap(); app.buttons["Тайский"].tap()
        let automaticSpeech = app.switches["Автоматически озвучивать"]
        let wasAutomatic = automaticSpeech.value as? String == "1"
        if !wasAutomatic { automaticSpeech.tap() }
        let editor = app.textViews["Текст оригинала"]
        editor.tap(); editor.typeText("Привет как дела?")
        XCTAssertEqual(editor.value as? String, "Привет как дела?")
        app.swipeDown()
        if app.buttons["Подготовить перевод"].exists { app.buttons["Подготовить перевод"].tap() }
        XCTAssertTrue(app.buttons["Перевести"].waitForExistence(timeout: 120))
        app.buttons["Перевести"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Скопировать перевод"])
        waitForExpectations(timeout: 120)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Выбрать исходный язык"])
        waitForExpectations(timeout: 120)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Actual RU TH greeting result"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Actual RU TH result hierarchy"; tree.lifetime = .keepAlways; add(tree)
        if !wasAutomatic { automaticSpeech.tap() }
    }

    @MainActor func testTextAutoAndNewVoicePlaybackCanBeStopped() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.segmentedControls.buttons["Текст"].tap()
        func choose(_ button: String, _ language: String) {
            app.buttons[button].tap(); app.buttons[language].tap()
        }
        choose("Выбрать исходный язык", "Английский")
        choose("Выбрать язык перевода", "Русский")
        let auto = app.switches["Автоопределение языка"]
        XCTAssertTrue(auto.exists)
        if auto.value as? String != "1" { auto.tap() }
        let editor = app.textViews["Текст оригинала"]
        editor.tap(); editor.typeText("Hello, please tell me where the railway station is. I would like to buy a ticket for tomorrow morning.")
        app.swipeDown()
        if app.buttons["Подготовить перевод"].exists { app.buttons["Подготовить перевод"].tap() }
        let translate = app.buttons["Перевести"]
        XCTAssertTrue(translate.waitForExistence(timeout: 120)); translate.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Скопировать перевод"])
        waitForExpectations(timeout: 120)
        if app.buttons["Остановить озвучку"].exists { app.buttons["Остановить озвучку"].tap() }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Выбрать исходный язык"])
        waitForExpectations(timeout: 60)
        let autoShot = XCTAttachment(screenshot: app.screenshot()); autoShot.name = "Automatic text translation"; autoShot.lifetime = .keepAlways; add(autoShot)
        for (language, text) in [
            ("Тайский", "สวัสดี นี่คือเสียงของฉัน รถไฟออกตอนห้าโมง สวัสดี นี่คือเสียงของฉัน รถไฟออกตอนห้าโมง"),
            ("Японский", "こんにちは。これが私の声です。電車は五時に出発します。こんにちは。これが私の声です。電車は五時に出発します。")
        ] {
            app.swipeDown()
            choose("Выбрать исходный язык", language)
            editor.tap()
            // Select the whole one-paragraph fixture; tapping alone may position the cursor at its start.
            editor.tap(withNumberOfTaps: 3, numberOfTouches: 1)
            editor.typeText(text)
            XCTAssertEqual(editor.value as? String, text)
            app.swipeDown()
            let speak = app.buttons["Озвучить оригинал"]
            XCTAssertTrue(speak.isEnabled); speak.tap()
            XCTAssertTrue(app.staticTexts["Озвучиваю…"].waitForExistence(timeout: 90), language)
            let stop = app.buttons["Остановить озвучку"]
            XCTAssertTrue(stop.isHittable); stop.tap()
            XCTAssertTrue(speak.waitForExistence(timeout: 15))
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: speak)
            waitForExpectations(timeout: 15)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = language + " speech stopped"; shot.lifetime = .keepAlways; add(shot)
        }
        app.swipeDown()
        choose("Выбрать исходный язык", "Русский"); choose("Выбрать язык перевода", "Английский")
    }

    @MainActor func testTextResultsStayInTextTabAndEitherCrossClearsBothFields() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-automaticSpeechText", "NO", "-automaticLanguage", "NO"]
        app.launch()
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        XCTAssertTrue(app.segmentedControls.buttons["Текст"].waitForExistence(timeout: 30))
        app.segmentedControls.buttons["Текст"].tap()
        app.buttons["Выбрать исходный язык"].tap(); app.buttons["Русский"].tap()
        app.buttons["Выбрать язык перевода"].tap(); app.buttons["Английский"].tap()
        let action = app.buttons["text.translate"]
        expectation(for: NSPredicate(format: "label == %@ OR label == %@", "Подготовить перевод", "Перевести"), evaluatedWith: action)
        waitForExpectations(timeout: 180)
        if action.label == "Подготовить перевод" { action.tap() }
        expectation(for: NSPredicate(format: "label == %@", "Перевести"), evaluatedWith: action)
        waitForExpectations(timeout: 180)
        let editor = app.textViews["Текст оригинала"]
        func reveal(_ element: XCUIElement) {
            for _ in 0..<5 { if element.isHittable { return }; app.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        for clearID in ["text.clear.target", "text.clear.source"] {
            editor.tap(); editor.typeText("Где находится вокзал?")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            XCTAssertTrue(action.isHittable)
            XCTAssertLessThanOrEqual(action.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            action.tap()
            let copy = app.buttons["Скопировать перевод"]
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: copy)
            waitForExpectations(timeout: 120)
            app.segmentedControls.buttons["Голос"].tap()
            XCTAssertFalse(app.staticTexts["voice.translation.text"].exists)
            XCTAssertFalse(app.buttons["Скопировать перевод"].exists)
            app.segmentedControls.buttons["Текст"].tap()
            XCTAssertEqual(editor.value as? String, "Где находится вокзал?")
            XCTAssertTrue(copy.isEnabled)
            let clear = app.buttons[clearID]; reveal(clear); clear.tap()
            XCTAssertTrue(editor.exists)
            XCTAssertEqual(editor.value as? String ?? "", "")
            XCTAssertFalse(copy.isEnabled)
            XCTAssertFalse(app.buttons["Скопировать оригинал"].isEnabled)
            XCTAssertFalse(action.isEnabled)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Both fields cleared via \(clearID)"; shot.lifetime = .keepAlways; add(shot)
            app.swipeDown()
        }
    }

    @MainActor func testDownloadAllLanguageVoices() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let settings = app.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30)); settings.tap()
        let voices = app.buttons["Голоса и образцы"]
        if !voices.isHittable { app.swipeUp() }
        XCTAssertTrue(voices.waitForExistence(timeout: 5)); voices.tap()
        let coverage = app.staticTexts["voices.coverage"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 30))
        let button = app.buttons["voices.downloadAll"]
        expectation(for: NSPredicate { _, _ in
            coverage.label.contains("14 из 14") || (button.exists && button.isEnabled)
        }, evaluatedWith: app)
        waitForExpectations(timeout: 120)
        if button.exists && button.isEnabled { button.tap() }
        expectation(for: NSPredicate(format: "label CONTAINS '14 из 14'"), evaluatedWith: coverage)
        waitForExpectations(timeout: 900)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "All voices installed"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testClearInputAndTranslateButtonAboveKeyboard() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.segmentedControls.buttons["Текст"].waitForExistence(timeout: 30))
        app.segmentedControls.buttons["Текст"].tap()
        let editor = app.textViews["Текст оригинала"]
        editor.tap(); editor.typeText("Where is the station?")
        let keyboard = app.keyboards.firstMatch, translate = app.buttons["text.translate"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(translate.isHittable)
        XCTAssertLessThanOrEqual(translate.frame.maxY, keyboard.frame.minY + 1)
        let clear = app.buttons["text.clear.source"]
        for _ in 0..<3 { if clear.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(clear.isHittable); clear.tap()
        XCTAssertTrue(editor.exists)
            XCTAssertEqual(editor.value as? String ?? "", "")
        XCTAssertFalse(app.buttons["Скопировать оригинал"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Clear field and pinned translate action"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testCameraControlsInBothLandscapeOrientations() throws {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.segmentedControls.buttons["Камера"].waitForExistence(timeout: 30))
        app.segmentedControls.buttons["Камера"].tap()
        let shutter = app.buttons["camera.capture"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true AND label == %@", "Снять и перевести"), evaluatedWith: shutter)
        waitForExpectations(timeout: 180)
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation != .portrait
            expectation(for: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return (frame.width > frame.height) == landscape
            }, evaluatedWith: app)
            waitForExpectations(timeout: 10)
            let controls = [shutter, app.buttons["camera.close"], app.buttons["Настройки распознавания"], app.buttons["Выбрать исходный язык"], app.buttons["Выбрать язык перевода"], app.buttons["Галерея"], app.buttons["Увеличение 1 крат"], app.buttons["Увеличение 2 крат"]]
            for control in controls {
                XCTAssertTrue(control.isHittable, control.label)
                XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(control.frame), "Outside screen: \(control.label) \(control.frame)")
            }
            for (index, a) in controls.enumerated() {
                for b in controls.dropFirst(index + 1) {
                    XCTAssertFalse(a.frame.insetBy(dx: 2, dy: 2).intersects(b.frame.insetBy(dx: 2, dy: 2)), "Overlapping controls: \(a.label), \(b.label)")
                }
            }
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "Camera geometry \(orientation.rawValue)"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Camera orientation \(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
            if landscape {
                shutter.tap()
                let resume = app.buttons["Вернуться к камере"]
                XCTAssertTrue(resume.waitForExistence(timeout: 15))
                for button in [resume, app.buttons["Сохранить"], app.buttons["Поделиться снимком"], app.buttons["Текст перевода"]] {
                    XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(button.frame), "Frozen control outside screen: \(button.label)")
                }
                let frozen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); frozen.name = "Landscape frozen photo \(orientation.rawValue)"; frozen.lifetime = .keepAlways; add(frozen)
                resume.tap()
                expectation(for: NSPredicate(format: "enabled == true AND label == %@", "Снять и перевести"), evaluatedWith: shutter)
                waitForExpectations(timeout: 30)
            }
        }
        app.buttons["camera.close"].tap()
    }

    @MainActor func testTextFieldActionsAndCameraShutterStayOnScreen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-showTechnicalInfo", "YES"]
        defer { app.terminate(); app.launchArguments = []; app.launch() }
        app.launch()
        let text = app.segmentedControls.buttons["Текст"]
        XCTAssertTrue(text.waitForExistence(timeout: 15)); text.tap()
        let sourceCopy = app.buttons["Скопировать оригинал"]
        let sourceSpeech = app.buttons["Озвучить оригинал"]
        let targetCopy = app.buttons["Скопировать перевод"]
        let targetSpeech = app.buttons["Озвучить перевод"]
        XCTAssertTrue(sourceCopy.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceSpeech.isHittable); XCTAssertTrue(targetSpeech.isHittable)
        XCTAssertTrue(sourceCopy.isHittable); XCTAssertTrue(targetCopy.isHittable)
        XCTAssertFalse(sourceCopy.isEnabled); XCTAssertFalse(targetCopy.isEnabled)
        let editor = app.textViews["Текст оригинала"]
        editor.tap(); editor.typeText("Hello")
        XCTAssertTrue(sourceCopy.isEnabled)
        // Keyboard dismissal must not require one of the old below-field action buttons.
        app.swipeDown()
        let textShot = XCTAttachment(screenshot: app.screenshot()); textShot.name = "Text fields"; textShot.lifetime = .keepAlways; add(textShot)
        app.segmentedControls.buttons["Камера"].tap()
        let shutter = app.buttons["camera.capture"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(shutter.frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(shutter.frame.maxY, screen.maxY)
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: shutter)
        waitForExpectations(timeout: 60)
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "Camera ready before hit test"; before.lifetime = .keepAlways; add(before)
        XCTAssertTrue(shutter.isHittable, "Ready shutter must be accessible without scrolling")
        XCTAssertFalse(app.segmentedControls.firstMatch.isHittable)
        app.buttons["Увеличение 2 крат"].tap()
        app.buttons["Увеличение 1 крат"].tap()
        let cameraShot = XCTAttachment(screenshot: app.screenshot()); cameraShot.name = "Camera viewport"; cameraShot.lifetime = .keepAlways; add(cameraShot)
        shutter.tap()
        XCTAssertTrue(app.buttons["Вернуться к камере"].waitForExistence(timeout: 10))
        let frozen = XCTAttachment(screenshot: app.screenshot()); frozen.name = "Frozen photo"; frozen.lifetime = .keepAlways; add(frozen)
        app.buttons["camera.close"].tap()
        XCTAssertTrue(sourceCopy.waitForExistence(timeout: 10))
        app.buttons["Отчёт и измерения"].tap()
        let memory = app.descendants(matching: .any)["diagnostics.memory"].firstMatch
        let memoryExists = memory.waitForExistence(timeout: 8)
        let debug = XCTAttachment(string: app.debugDescription); debug.name = "Diagnostics hierarchy"; debug.lifetime = .keepAlways; add(debug)
        let diagnostic = XCTAttachment(screenshot: app.screenshot()); diagnostic.name = "Resource diagnostics"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTAssertTrue(memoryExists)
        XCTAssertTrue(app.descendants(matching: .any)["diagnostics.storage.free"].firstMatch.exists)
        app.buttons["Готово"].tap()
    }
}
