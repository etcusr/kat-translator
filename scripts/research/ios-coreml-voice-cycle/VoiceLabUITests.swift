import XCTest

final class TranslatorUITests: XCTestCase {
    @MainActor func testFileImportHiddenWithoutDiagnostics() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-showTechnicalInfo", "NO"]
        app.launchEnvironment = ["LAB_VARIANT": "q8"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["voice.record"].waitForExistence(timeout: 300))
        XCTAssertFalse(app.buttons["voice.import"].exists)
    }

    @MainActor func testFileImport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-showTechnicalInfo", "YES"]
        let variant = ProcessInfo.processInfo.environment["LAB_VARIANT"] ?? "coreml-q8"
        let speak = ProcessInfo.processInfo.environment["LAB_SPEAK"] == "1"
        app.launchEnvironment = ["LAB_VARIANT": variant, "LAB_BASELINE": variant == "f16" ? "1" : "0",
                                 "LAB_SPEAK": speak ? "1" : "0"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["voice.record"].waitForExistence(timeout: 300))
        let importer = app.buttons["voice.import"]
        XCTAssertTrue(importer.waitForExistence(timeout: 15), "Diagnostic audio-file input must be available")
        guard importer.exists else { return }
        let repetitions = Int(ProcessInfo.processInfo.environment["LAB_FILE_REPEATS"] ?? "2") ?? 2
        for repetition in 0..<repetitions {
            for name in ["01-date", "02-time-first", "03-date-first", "04-long"] {
                if !importer.waitForExistence(timeout: 2), app.buttons["voice.prepare"].exists {
                    // Exercise the existing recovery button; report this intervention explicitly.
                    print("VOICE_LAB_MANUAL_PREPARE_\(repetition)_\(name)")
                    app.buttons["voice.prepare"].tap()
                }
                XCTAssertTrue(importer.waitForExistence(timeout: 240))
                let previousTranslation = app.staticTexts["voice.translation.text"].exists
                    ? app.staticTexts["voice.translation.text"].label : ""
                importer.tap()
                let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
                if !file.waitForExistence(timeout: 3) {
                    let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "Обзор"])).firstMatch
                    XCTAssertTrue(browse.waitForExistence(timeout: 10), app.debugDescription)
                    browse.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    let lab = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Kat Voice Lab")).firstMatch
                    if !lab.waitForExistence(timeout: 2) {
                        let local = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "On My iPhone")).firstMatch
                        XCTAssertTrue(local.waitForExistence(timeout: 10), app.debugDescription)
                        local.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                    for label in ["Kat Voice Lab", "AudioTests"] {
                        let item = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
                        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
                        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                }
                XCTAssertTrue(file.waitForExistence(timeout: 20), app.debugDescription)
                file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    ((importer.exists && importer.isEnabled)
                        || (app.buttons["voice.prepare"].exists && app.buttons["voice.prepare"].isEnabled))
                        && app.staticTexts["voice.translation.text"].exists
                        && app.staticTexts["voice.translation.text"].label != previousTranslation
                        && (!speak || (app.buttons["voice.translation.shareAudio"].isEnabled
                            && app.buttons["voice.playback.startStop"].label == "Озвучить перевод"))
                        && !app.buttons["voice.playback.pauseResume"].exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 240), .completed, app.debugDescription)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "file-\(name)-\(repetition)"; screenshot.lifetime = .keepAlways; add(screenshot)
                print("VOICE_LAB_FILE_FINISHED_\(repetition)_\(name)")
            }
        }
    }

    @MainActor func testVoiceLab() throws {
        guard ProcessInfo.processInfo.environment["LAB_ACOUSTIC"] == "1" else {
            throw XCTSkip("Acoustic microphone/playback checks require an explicit run.py invocation")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        let baseline = ProcessInfo.processInfo.environment["LAB_BASELINE"] == "1"
        let dates = ProcessInfo.processInfo.environment["LAB_DATES"] == "1"
        app.launchEnvironment = ["LAB_BASELINE": baseline ? "1" : "0", "LAB_SPEAK": "1", "NSUnbufferedIO": "YES"]
        app.launch()
        defer { app.terminate() }
        let permission = addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Разрешить", "OK", "ОК"])).firstMatch
            if allow.exists { allow.tap(); return true }
            return false
        }
        defer { removeUIInterruptionMonitor(permission) }
        let record = app.buttons["voice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 300), app.debugDescription)
        for cycle in 0..<4 {
            XCTAssertTrue(record.isEnabled)
            record.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Разрешить", "OK", "ОК"])).firstMatch
            if allow.waitForExistence(timeout: 2) { allow.tap() }
            XCTAssertTrue(app.buttons["voice.pauseResume"].waitForExistence(timeout: 30), app.debugDescription)
            print("VOICE_LAB_CAPTURE_READY_\(cycle)")
            // Host loudspeaker supplies actual acoustic input; never import it into the app.
            Thread.sleep(forTimeInterval: cycle == 3 ? 32 : (dates ? 16 : 14))
            XCTAssertEqual(record.label, "Завершить запись")
            print("VOICE_LAB_PLAYBACK_READY_\(cycle)")
            Thread.sleep(forTimeInterval: 2)
            record.tap()
            let playback = app.buttons["voice.playback.startStop"]
            let share = app.buttons["voice.translation.shareAudio"]
            let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let translated = app.staticTexts["voice.translation.text"]
                return translated.exists && translated.label.count > 5
                    && playback.exists && playback.label == "Озвучить перевод"
                    && share.exists && share.isEnabled
                    && !app.buttons["voice.playback.pauseResume"].exists
                    && !app.buttons["voice.pauseResume"].exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 240), .completed, app.debugDescription)
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Модели выгружены")).firstMatch.exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "voice-lab-cycle-\(cycle)"; screenshot.lifetime = .keepAlways; add(screenshot)
            print("VOICE_LAB_CYCLE_FINISHED_\(cycle)")
            Thread.sleep(forTimeInterval: 3)
        }
        // Capture must still work after prior cycles, including any memory recovery.
        XCTAssertTrue(record.isEnabled); record.tap()
        XCTAssertTrue(app.buttons["voice.pauseResume"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.buttons["voice.pauseResume"].exists)
        print("VOICE_LAB_REPEAT_CAPTURE_OK")
    }
}
