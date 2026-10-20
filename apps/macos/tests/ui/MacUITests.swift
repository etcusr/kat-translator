import XCTest
import AppKit
import Carbon
final class MacUITests: XCTestCase {
    /// Line starts inside a panel: every element that begins a line must start on a text edge
    /// shared with other lines. A lone start 4–24 pt off the nearest edge is the "not quite even"
    /// look (button insets, stray padding); larger offsets are icons or nested content. Same rule
    /// as the iOS audit.
    @MainActor private func misalignedLineStarts(in scope: XCUIElement, screen: String) -> [String] {
        let bounds = scope.frame
        let items = (scope.staticTexts.allElementsBoundByIndex + scope.buttons.allElementsBoundByIndex
                     + scope.checkBoxes.allElementsBoundByIndex + scope.switches.allElementsBoundByIndex)
            .map { ($0.label, $0.frame) }
            .filter { !$0.1.isEmpty && $0.1.width < bounds.width - 1 && $0.1.minY >= bounds.minY + 50 && $0.1.maxY <= bounds.maxY - 120 && $0.1.minX < bounds.midX }
        func overlaps(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) / 2 }
        let leaves = items.filter { item in !items.contains { $0.1 != item.1 && item.1.contains($0.1) } }
        let starts = leaves.filter { item in !leaves.contains { $0.1 != item.1 && overlaps($0.1, item.1) && $0.1.minX < item.1.minX - 1 } }
        let counts = Dictionary(grouping: starts) { Int($0.1.minX.rounded()) }.mapValues(\.count)
        let edges = counts.filter { $0.value >= 2 }.keys
        return starts.compactMap { item in
            let x = Int(item.1.minX.rounded())
            guard counts[x] == 1, let edge = edges.min(by: { abs($0 - x) < abs($1 - x) }) else { return nil }
            let offset = x - edge
            return abs(offset) > 4 && abs(offset) < 24 ? "\(screen): «\(item.0.prefix(50))» starts \(offset) pt from the text edge (x \(x), edge \(edge))" : nil
        }
    }

    /// Opt-in (KAT_STORE_SHOTS=1): App Store screenshots of the current test-built app in
    /// each supported UI language. Text-history recording is disabled via its typed UI
    /// control and restored; other overrides stay in the argument domain. The caller
    /// verifies persisted preferences/history before and after; the pasteboard is restored.
    @MainActor func testStoreScreenshots() throws {
        try captureStoreScreenshots(language: ProcessInfo.processInfo.environment["KAT_STORE_SHOTS_LANG"] ?? "ru")
    }

    @MainActor func testStoreScreenshotsAllLanguages() throws {
        for language in ["ru", "en", "es", "tr"] {
            try captureStoreScreenshots(language: language)
        }
    }

    @MainActor private func captureStoreScreenshots(language: String) throws {
        guard ProcessInfo.processInfo.environment["KAT_STORE_SHOTS"] == "1" else { throw XCTSkip("Opt-in store screenshots") }
        let labels = try XCTUnwrap(["ru": (settings: "Настройки", models: "Модели"),
                      "en": (settings: "Settings", models: "Models"),
                      "es": (settings: "Ajustes", models: "Modelos"),
                      "tr": (settings: "Ayarlar", models: "Modeller")][language], "Unsupported store screenshot language: \(language)")
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        // KAT_STORE_SHOTS_APP: a separately built copy, so the installed app is never replaced.
        let app = environment["KAT_STORE_SHOTS_APP"].map { XCUIApplication(url: URL(fileURLWithPath: $0)) } ?? XCUIApplication()
        // Interface language → (source, target, sample text, word expected in the translation).
        let samples: [String: (String, String, String, String)] = [
            "ru": ("ru", "en", "Поезд до Казани отправится завтра в 07:45 с третьего пути. Пожалуйста, возьмите с собой паспорт и билет.", "train"),
            "en": ("en", "es", "The train to Madrid leaves tomorrow at 7:45 from platform 3. Please bring your passport and ticket.", "tren"),
            "es": ("es", "en", "El tren a Sevilla sale mañana a las 7:45 desde el andén 3. Por favor, lleve su pasaporte y su billete.", "train"),
            "tr": ("tr", "en", "İzmir treni yarın saat 07:45'te üçüncü perondan kalkacak. Lütfen pasaportunuzu ve biletinizi yanınızda getirin.", "train")]
        let (source, target, sample, expected) = try XCTUnwrap(samples[language])
        app.launchArguments = ["-languageSetupCompleted", "YES", "-appInterfaceLanguage", language, "-ApplePersistenceIgnoreState", "YES",
                               "-automaticModelLoad", "NO", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-translationSource", source, "-translationTarget", target, "-automaticLanguage", "NO", "-automaticSpeechText", "NO",
                               "-showTechnicalInfo", "NO"]   // store shots without the diagnostics toolbar, model line and timings
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { app.terminate(); if board.string(forType: .string) == sample { board.clearContents(); board.writeObjects(saved) } }
        app.launch()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 60))
        var historyBeforeCapture: Bool?
        func switchState(_ control: XCUIElement) -> Bool? {
            if let number = control.value as? NSNumber { return number.boolValue }
            if let string = control.value as? String {
                switch string.lowercased() {
                case "1", "true", "on": return true
                case "0", "false", "off": return false
                default: return nil
                }
            }
            return nil
        }
        func textHistory(_ enabled: Bool) throws {
            let settings = app.buttons[labels.settings].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 60)); settings.click()
            XCTAssertTrue(app.buttons["settings.close"].waitForExistence(timeout: 30))
            let control = app.switches["history.recordText"]
            for _ in 0..<12 where !control.isHittable {
                app.sheets.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -650)
            }
            XCTAssertTrue(control.isHittable)
            let previous = try XCTUnwrap(switchState(control), "Unrecognized history Switch value; refusing to enter sample text")
            if historyBeforeCapture == nil { historyBeforeCapture = previous }
            if previous != enabled {
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).click()
            }
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in switchState(control) == enabled }, object: control)
            guard XCTWaiter.wait(for: [changed], timeout: 5) == .completed else {
                throw NSError(domain: "StoreScreenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "History switch did not reach the required state"])
            }
            XCTAssertEqual(try XCTUnwrap(switchState(control)), enabled)
            app.buttons["settings.close"].click()
        }
        // Install restoration before the first toggle, including its failing assertion path.
        defer {
            if let originalHistory = historyBeforeCapture {
                app.terminate(); app.launch()
                do { try textHistory(originalHistory) }
                catch { XCTFail("Could not restore history recording: \(error)") }
                app.terminate()
            }
        }
        try textHistory(false)
        // 1440×900 pt: an accepted Mac App Store size (2880×1800 on a Retina screen). XCUITest
        // could not capture a window moved to a second display, so the window stays where it opens.
        let window = app.windows.firstMatch
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.3, thenDragTo: corner.withOffset(CGVector(dx: 1440 - window.frame.width, dy: 900 - window.frame.height)))
        func shot(_ name: String) {
            Thread.sleep(forTimeInterval: 1.5)
            let image = XCTAttachment(screenshot: window.screenshot()); image.name = "store-\(language)-" + name; image.lifetime = .keepAlways; add(image)
        }
        app.buttons["mode.text"].click()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(editor.frame.minX.isFinite && editor.frame.minY.isFinite && editor.frame.width.isFinite && editor.frame.height.isFinite && !editor.frame.isEmpty)
        editor.click(); board.clearContents(); XCTAssertTrue(board.setString(sample, forType: .string))
        app.typeKey("v", modifierFlags: .command)
        let inserted = NSPredicate(format: "value == %@", sample)
        if !inserted.evaluate(with: editor) {
            // A keyboard-layout mismatch can drop Cmd-V. Use the app's real Paste action.
            app.menuBars.menuBarItems["Edit"].click()
            let paste = app.menuItems["Paste"].firstMatch
            XCTAssertTrue(paste.waitForExistence(timeout: 5)); XCTAssertTrue(paste.isEnabled)
            paste.click()
        }
        let hasInput = XCTNSPredicateExpectation(predicate: inserted, object: editor)
        guard XCTWaiter.wait(for: [hasInput], timeout: 5) == .completed else {
            shot("diagnostic-input")
            XCTFail("Sample text did not reach the editor; translation was not started")
            return
        }
        // The first press may only prepare the model; never press a temporary Cancel action.
        let translate = app.buttons["text.translate"]
        let output = app.staticTexts["text.translation.text"]
        func done() -> Bool { output.exists && ((output.value as? String ?? "") + " " + output.label).lowercased().contains(expected) }
        let allowedActions = try XCTUnwrap([
            "ru": ["Подготовить перевод", "Перевести"],
            "en": ["Prepare translation", "Translate"],
            "es": ["Preparar traducción", "Traducir"],
            "tr": ["Çeviriyi hazırla", "Çevir"]][language])
        let deadline = Date().addingTimeInterval(240)
        while !done() && Date() < deadline {
            if translate.exists && translate.isEnabled && translate.isHittable && allowedActions.contains(translate.label) { translate.click() }
            Thread.sleep(forTimeInterval: 3)
        }
        if !done() { shot("diagnostic-translation") }
        XCTAssertTrue(done(), "translation did not appear")
        shot("1-text")
        app.buttons["mode.voice"].click()
        shot("2-voice")
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Модели", "Models", "Modelos", "Modeller"])).firstMatch.click()
        XCTAssertTrue(app.buttons["models.languageSetup"].waitForExistence(timeout: 10))
        shot("3-models")
        app.buttons["models.languageSetup"].click()
        XCTAssertTrue(app.textFields["setup.search.targets"].waitForExistence(timeout: 30))
        shot("4-languages")
        app.buttons["setup.close"].click()
        let opus = app.buttons["opus.directions.open"]
        let sheet = app.sheets.firstMatch
        for _ in 0..<15 where !(opus.exists && opus.isHittable) { sheet.scroll(byDeltaX: 0, deltaY: -200) }
        if opus.exists && opus.isHittable {
            opus.click()
            if app.textFields["opus.search"].waitForExistence(timeout: 10) { shot("5-opus-directions") }
        }
    }

    /// Read-only audit of the language setup panel (the screen reported as uneven on Mac).
    @MainActor func testLanguageSetupAlignsLineStartsAndActions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "ru"]
        app.launch(); defer { app.terminate() }
        let models = app.buttons.matching(NSPredicate(format: "label IN %@", ["Модели", "Models"])).firstMatch
        XCTAssertTrue(models.waitForExistence(timeout: 60)); models.click()
        XCTAssertTrue(app.buttons["models.languageSetup"].waitForExistence(timeout: 10))
        app.buttons["models.languageSetup"].click()
        XCTAssertTrue(app.textFields["setup.search.targets"].waitForExistence(timeout: 30))
        let panel = app.sheets.containing(.textField, identifier: "setup.search.targets").firstMatch
        let done = app.buttons["setup.done"], download = app.buttons["setup.download"]
        if done.exists { XCTAssertEqual(done.frame.width, download.frame.width, accuracy: 1, "Download and Done widths differ") }
        var problems = Set<String>()
        for step in 0..<4 {
            problems.formUnion(misalignedLineStarts(in: panel, screen: "setup"))
            let shot = XCTAttachment(screenshot: panel.screenshot()); shot.name = "mac-setup-\(step)"; shot.lifetime = .keepAlways; add(shot)
            panel.scroll(byDeltaX: 0, deltaY: -300)
        }
        // Sizes in the models card sit at its right text edge (LabeledContent once put them next to the names).
        // macOS exposes the card as a group (iOS: an other element).
        let card = app.groups["setup.panel.models"]
        // Queried app-wide: on macOS the card container does not expose its texts as children.
        let sizes = app.staticTexts.matching(identifier: "setup.size")
        for size in sizes.allElementsBoundByIndex where card.exists {
            if abs(card.frame.maxX - 16 - size.frame.maxX) > 2 { problems.insert("setup: size «\(size.label)» ends \(Int(card.frame.maxX - 16 - size.frame.maxX)) pt left of the card edge") }
        }
        XCTAssertTrue(card.exists && sizes.count > 0, "Model sizes must be listed")
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
        app.buttons["setup.close"].click()
    }
    @MainActor func testLanguageSpecificVoicePreviewButtons() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en"]
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Settings"].firstMatch.click()
        app.buttons["Voices and samples"].click()
        let samples = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'voices.preview.'"))
        XCTAssertTrue(samples.firstMatch.waitForExistence(timeout: 10))
        var checked = Set<String>()
        let supertonic = "sherpa-onnx-supertonic-3-tts-int8-2026-05-11"
        XCTAssertEqual(app.buttons.matching(identifier: "voices.preview.en." + supertonic).count, 1,
                       "Shared voice rows must not inherit the English row's identity or action")
        XCTAssertEqual(app.buttons.matching(identifier: "voices.preview.de." + supertonic).count, 1)
        for (code, voice) in [("en", supertonic), ("zh", "vits-piper-zh_CN-huayan-medium"), ("de", supertonic), ("fr", supertonic), ("es", supertonic)] {
            let id = "voices.preview." + code + "." + voice
            let button = app.buttons[id]
            for _ in 0..<15 where !button.isHittable { app.sheets.firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -280) }
            XCTAssertTrue(button.isHittable, id)
            button.click()
            XCTAssertEqual(button.label, "Stop sample", id)
            // These samples last only a few seconds; let them finish before the next row.
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Play sample'"), object: button)], timeout: 15), .completed, id)
            checked.insert(id)
        }
        let report = XCTAttachment(string: checked.sorted().joined(separator: "\n"))
        report.name = "Voice preview button routes"; report.lifetime = .keepAlways; add(report)
    }
    @MainActor func testImageTimingVisibility() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { original in
            let item = NSPasteboardItem()
            for type in original.types { if let data = original.data(forType: type) { item.setData(data, forType: type) } }
            return item
        }
        defer { app.terminate(); board.clearContents(); if !saved.isEmpty { board.writeObjects(saved) } }
        let fixture = NSImage(size: NSSize(width: 1000, height: 220), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            for (text, y) in [("The museum brings together art,", 120.0), ("science and technology.", 70.0)] {
                (text as NSString).draw(at: NSPoint(x: 30, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 38), .foregroundColor: NSColor.black])
            }
            return true
        }
        let cg = try XCTUnwrap(fixture.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        for enabled in [true, false] {
            app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-historyRecordImages", "NO", "-showTechnicalInfo", enabled ? "YES" : "NO"]
            app.launch()
            XCTAssertTrue(app.buttons["mode.camera"].waitForExistence(timeout: 25)); app.buttons["mode.camera"].click()
            XCTAssertFalse(app.staticTexts["image.timing"].exists)
            board.clearContents(); board.setData(data, forType: .png)
            app.buttons["Paste image"].click()
            let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["image.saveTranslation"])
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 90), .completed)
            let text = app.textViews["image.translation"].value as? String ?? ""
            XCTAssertTrue(text.lowercased().contains("музе"), text)
            XCTAssertFalse(text.contains("\n"), text)
            XCTAssertEqual(app.staticTexts["image.timing"].exists, enabled)
            if enabled {
                let label = (app.staticTexts["image.timing"].value as? String) ?? app.staticTexts["image.timing"].label
                XCTAssertTrue(label.contains("Recognition:"), label)
                XCTAssertTrue(label.contains("Translation:"), label)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = enabled ? "Image diagnostics on" : "Image diagnostics off"; screenshot.lifetime = .keepAlways; add(screenshot)
            app.terminate()
        }
    }

    @MainActor func testImageTranslationReaderAndActions() throws {
        continueAfterFailure = false
        let previousInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        _ = TISSelectInputSource(TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue())
        defer { _ = TISSelectInputSource(previousInput) }
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-historyRecordImages", "NO"]
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { original in
            let item = NSPasteboardItem()
            for type in original.types { if let data = original.data(forType: type) { item.setData(data, forType: type) } }
            return item
        }
        defer { app.terminate(); board.clearContents(); if !saved.isEmpty { board.writeObjects(saved) } }
        app.launch()
        XCTAssertTrue(app.buttons["mode.camera"].waitForExistence(timeout: 25)); app.buttons["mode.camera"].click()
        let copy = app.buttons["image.copyTranslation"], share = app.buttons["image.shareTranslation"], save = app.buttons["image.saveTranslation"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(share.isEnabled); XCTAssertFalse(save.isEnabled)
        let fixture = NSImage(size: NSSize(width: 820, height: 220), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("The library opens at nine." as NSString).draw(at: NSPoint(x: 35, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
            return true
        }
        let cg = try XCTUnwrap(fixture.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        board.clearContents(); board.setData(data, forType: .png)
        app.buttons["Paste image"].click()
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 90), .completed)
        let translated = app.textViews["image.translation"].value as? String ?? ""
        XCTAssertTrue(translated.lowercased().contains("библиотек"), translated)
        let expand = app.buttons["image.translation.expand"]
        XCTAssertTrue(expand.exists)
        for button in [expand, copy, share, save] {
            XCTAssertTrue(button.isEnabled)
            XCTAssertEqual(button.frame.midY, save.frame.midY, accuracy: 1)
            XCTAssertEqual(button.frame.width, save.frame.width, accuracy: 1)
        }
        let edited = "Library opens at nine."
        let resultEditor = app.textViews["image.translation"]
        resultEditor.click(); resultEditor.typeKey("a", modifierFlags: .command)
        board.clearContents(); board.setString(edited, forType: .string)
        resultEditor.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(resultEditor.value as? String, edited)
        copy.click(); XCTAssertEqual(board.string(forType: .string), edited)
        let normal = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); normal.name = "image-actions"; normal.lifetime = .keepAlways; add(normal)
        share.click()
        let sharingMenu = app.popovers["ShareSheet.Popover"].buttons["AirDrop"]
        XCTAssertTrue(sharingMenu.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["share.close"].exists, "Sharing must open directly without the intermediate export sheet")
        let sharing = XCTAttachment(screenshot: app.screenshot()); sharing.name = "image-direct-share"; sharing.lifetime = .keepAlways; add(sharing)
        app.typeKey(.escape, modifierFlags: [])
        save.click()
        XCTAssertTrue(app.dialogs.firstMatch.waitForExistence(timeout: 5) || app.sheets.firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
        expand.click()
        let close = app.buttons["reader.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let reading = app.staticTexts["reader.text"]
        XCTAssertEqual(reading.value as? String ?? reading.label, edited)
        XCTAssertGreaterThan(app.scrollViews["reader.scroll"].frame.width, app.windows.firstMatch.frame.width * 0.9)
        let full = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); full.name = "image-reader"; full.lifetime = .keepAlways; add(full)
        close.click()
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); XCTAssertTrue(app.images["image.original"].exists)
        XCTAssertEqual(app.textViews["image.translation"].value as? String, edited)
        expand.click(); XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); XCTAssertTrue(app.images["image.original"].exists)
    }
    @MainActor func testInstalledSelectionFromBraveAndSublime() async throws {
        guard ProcessInfo.processInfo.environment["KAT_VERIFY_EXTERNAL"] == "1" else { throw XCTSkip("Requires user-granted permissions") }
        continueAfterFailure = false
        let app = XCUIApplication(url: URL(fileURLWithPath: "/Applications/Kat translator.app"))
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "ru", "-translationTarget", "en", "-quickTranslationTarget", "ru", "-automaticLanguage", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        let oldInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        _ = TISSelectInputSource(TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue())
        let board = NSPasteboard.general
        let clipboard = (board.pasteboardItems ?? []).map { original in
            let item = NSPasteboardItem()
            for type in original.types { if let data = original.data(forType: type) { item.setData(data, forType: type) } }
            return item
        }
        addTeardownBlock { @MainActor in
            _ = TISSelectInputSource(oldInput)
            board.clearContents(); if !clipboard.isEmpty { board.writeObjects(clipboard) }
            app.terminate(); NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Kat translator.app"))
        }
        app.launch()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 15))
        let sample = "The library opens at nine."
        for (name, bundle, suffix) in [("Brave Browser", "com.brave.Browser", "html"), ("Sublime Text", "com.sublimetext.4", "txt")] {
            let token = "Kat-selection-" + UUID().uuidString
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(token + "." + suffix)
            let contents = suffix == "html" ? "<html><head><title>" + token + "</title></head><body style='font-size:30px;padding:50px'><p>" + sample + "</p></body></html>" : sample
            try contents.write(to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }
            _ = try await NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/Applications/" + name + ".app"), configuration: NSWorkspace.OpenConfiguration())
            let external = XCUIApplication(bundleIdentifier: bundle)
            external.activate()
            let document = external.windows.matching(NSPredicate(format: "title CONTAINS %@", token)).firstMatch
            XCTAssertTrue(document.waitForExistence(timeout: 10), external.debugDescription)
            addTeardownBlock { @MainActor in
                if document.exists { external.activate(); document.click(); external.typeKey("w", modifierFlags: .command) }
                try? FileManager.default.removeItem(at: file)
            }
            if suffix == "html" { document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click() }
            external.typeKey("a", modifierFlags: .command)
            board.clearContents(); board.setString("Clipboard sentinel", forType: .string)
            external.typeKey("t", modifierFlags: [.control, .shift])
            let quick = app.dialogs["Quick translation"]
            XCTAssertTrue(quick.waitForExistence(timeout: 10))
            XCTAssertEqual((quick.textViews["quick.original"].value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), sample, quick.debugDescription)
            XCTAssertEqual(board.string(forType: .string), "Clipboard sentinel")
            let translated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let result = quick.staticTexts["quick.translation"]
                return result.exists && (result.value as? String ?? result.label).lowercased().contains("библиотек")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [translated], timeout: 90), .completed)
            XCTAssertTrue(quick.buttons["quick.sourceLanguage"].exists)
            XCTAssertTrue(quick.buttons["quick.targetLanguage"].exists)
            let shot = XCTAttachment(screenshot: quick.screenshot()); shot.name = name + " selection"; shot.lifetime = .keepAlways; add(shot)
            quick.buttons["quick.close"].click()
        }
    }
    /// Opt-in check against the installed app, after the user grants macOS permissions.
    @MainActor func testInstalledExternalSelectionAndScreenRegion() async throws {
        guard ProcessInfo.processInfo.environment["KAT_VERIFY_EXTERNAL"] == "1" else { throw XCTSkip("Requires user-granted permissions") }
        continueAfterFailure = false
        let previousInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        _ = TISSelectInputSource(TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue())
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Kat-integration-" + UUID().uuidString + ".rtf")
        let sample = "The library opens at nine."
        let rich = NSAttributedString(string: sample, attributes: [.font: NSFont.systemFont(ofSize: 30)])
        try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: fixture)
        let app = XCUIApplication(url: URL(fileURLWithPath: "/Applications/Kat translator.app"))
        let external = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-historyRecordImages", "NO"]
        addTeardownBlock { @MainActor in
            _ = TISSelectInputSource(previousInput)
            try? FileManager.default.removeItem(at: fixture)
            app.terminate()
            let document = external.windows.matching(NSPredicate(format: "title CONTAINS %@", fixture.deletingPathExtension().lastPathComponent)).firstMatch
            if document.exists { external.activate(); document.buttons["_XCUI:CloseWindow"].click() }
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Kat translator.app"))
        }
        app.launch()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 15))
        _ = try await NSWorkspace.shared.open([fixture], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration())
        external.activate()
        let document = external.windows.matching(NSPredicate(format: "title CONTAINS %@", fixture.deletingPathExtension().lastPathComponent)).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 10))
        let editor = document.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.click()
        external.typeKey("a", modifierFlags: .command)
        let clipboardChanges = NSPasteboard.general.changeCount
        if ProcessInfo.processInfo.environment["KAT_SCREEN_ONLY"] != "1" {
        external.typeKey("t", modifierFlags: [.control, .shift])
        let quick = app.dialogs["Quick translation"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        XCTAssertEqual(quick.textViews["quick.original"].value as? String, sample, quick.debugDescription)
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let output = quick.staticTexts["quick.translation"]
            return output.exists && (output.value as? String ?? output.label).lowercased().contains("библиотек")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [translated], timeout: 90), .completed)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChanges)
        let shot = XCTAttachment(screenshot: quick.screenshot()); shot.name = "installed-selected-text"; shot.lifetime = .keepAlways; add(shot)
        quick.buttons["quick.close"].click()
        let serviceBoard = NSPasteboard.withUniqueName()
        defer { serviceBoard.releaseGlobally() }
        serviceBoard.setString(sample, forType: .string)
        XCTAssertTrue(NSPerformService("Translate in Kat translator", serviceBoard))
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        XCTAssertEqual(quick.textViews["quick.original"].value as? String, sample)
        let serviceDone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: quick.buttons["quick.translate"])
        XCTAssertEqual(XCTWaiter.wait(for: [serviceDone], timeout: 90), .completed)
        quick.buttons["quick.close"].click()
        }
        external.activate(); editor.click(); external.typeKey(.rightArrow, modifierFlags: [])
        let crop = editor.frame.insetBy(dx: 8, dy: 8)
        external.typeKey("s", modifierFlags: [.control, .shift])
        let overlayReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (app.windows.allElementsBoundByIndex + app.dialogs.allElementsBoundByIndex).contains { $0.frame.width > 1500 }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [overlayReady], timeout: 10), .completed)
        let overlay = try XCTUnwrap((app.windows.allElementsBoundByIndex + app.dialogs.allElementsBoundByIndex).first { $0.frame.width > 1500 })
        let origin = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let start = origin.withOffset(CGVector(dx: crop.minX - overlay.frame.minX, dy: crop.minY - overlay.frame.minY))
        let end = origin.withOffset(CGVector(dx: crop.maxX - overlay.frame.minX, dy: min(crop.maxY, crop.minY + 210) - overlay.frame.minY))
        start.press(forDuration: 0.15, thenDragTo: end)
        XCTAssertTrue(app.images["image.original"].waitForExistence(timeout: 10))
        let imageTranslated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (app.textViews["image.translation"].value as? String ?? "").lowercased().contains("библиотек")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [imageTranslated], timeout: 90), .completed)
        let imageShot = XCTAttachment(screenshot: app.windows["Kat translator"].screenshot()); imageShot.name = "installed-screen-translation"; imageShot.lifetime = .keepAlways; add(imageShot)
        external.activate(); document.buttons["_XCUI:CloseWindow"].click()
    }
    /// Explicitly opted-in manual check: leaves the OS prompt for the user to approve.
    @MainActor func testRequestInstalledIntegrationPermission() throws {
        guard let feature = ProcessInfo.processInfo.environment["KAT_REQUEST_PERMISSION"],
              ["selection", "screen"].contains(feature) else { throw XCTSkip("Manual permission check only") }
        let app = XCUIApplication(url: URL(fileURLWithPath: "/Applications/Kat translator.app"))
        app.activate()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 15))
        let menu = app.menuBars.menuBarItems.matching(NSPredicate(format: "title IN %@", ["Быстрый перевод", "Quick translation"])).firstMatch
        menu.click()
        let titles = feature == "selection" ? ["Перевести выделенный текст", "Translate selected text"] : ["Перевести область экрана", "Translate screen region"]
        app.menuItems.matching(NSPredicate(format: "title IN %@", titles)).firstMatch.click()
    }
    @MainActor func testConfigurableHotkeysAndMainWindowTranslation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-ApplePersistenceIgnoreState", "YES", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        let previousInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let asciiInput = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
        XCTAssertEqual(TISSelectInputSource(asciiInput), noErr)
        addTeardownBlock { @MainActor in TISSelectInputSource(previousInput) }
        let suite = "kat-hotkeys-ui-" + UUID().uuidString
        app.launchEnvironment["KAT_SHORTCUTS_TEST_SUITE"] = suite
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        let mainText = "Keep this unfinished text in the main window."
        let quickText = "The library opens at nine."
        addTeardownBlock { @MainActor in
            app.terminate()
            preferences.removePersistentDomain(forName: suite)
            preferences.synchronize()
            if [mainText, quickText].contains(board.string(forType: .string) ?? "") { board.clearContents(); board.writeObjects(saved) }
        }
        app.launch()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30)); app.buttons["mode.text"].click()
        let editor = app.textViews["Original text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.click()
        board.clearContents(); board.setString(mainText, forType: .string)
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        app.buttons["Settings"].firstMatch.click()
        let settings = app.buttons["settings.shortcuts"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.click()
        for (action, label) in [("selectedText", "⌥1"), ("screenRegion", "⌥2"), ("clipboardText", "⌥3")] {
            XCTAssertEqual(app.buttons["shortcuts.record." + action].label, label)
        }
        // The host may reserve Option+digits. Use a custom free binding for the
        // translation exercise without changing the user's system shortcuts.
        let clipboard = app.buttons["shortcuts.record.clipboardText"]
        clipboard.click()
        XCTAssertTrue(app.staticTexts["Press a new keyboard shortcut"].waitForExistence(timeout: 5))
        app.typeKey("v", modifierFlags: [.control, .shift])
        XCTAssertTrue(app.staticTexts["Press a new keyboard shortcut"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(clipboard.label, "⌃⇧V")
        let submit = app.buttons["shortcuts.record.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10)); submit.click()
        XCTAssertTrue(app.staticTexts["Press a new keyboard shortcut"].waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Press a new keyboard shortcut"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(submit.label, "⌘Enter")
        // The recorder accepts all four modifiers, not only three physical keys.
        let selection = app.buttons["shortcuts.record.selectedText"]
        selection.click(); XCTAssertTrue(app.staticTexts["Press a new keyboard shortcut"].waitForExistence(timeout: 5)); app.typeKey(.return, modifierFlags: [.control, .option, .shift, .command])
        XCTAssertTrue(app.staticTexts["Press a new keyboard shortcut"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(selection.label, "⌃⌥⇧⌘Enter")
        let shot = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot()); shot.name = "hotkey-settings"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["settings.close"].click()
        let hint = app.staticTexts["text.submit.hint"]
        XCTAssertTrue((hint.value as? String ?? hint.label).contains("⌘Enter"))
        let statusIcon = app.statusItems.firstMatch
        XCTAssertTrue(statusIcon.waitForExistence(timeout: 5), app.debugDescription)
        statusIcon.click()
        let menuShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menuShot.name = "status-menu-custom-shortcuts"; menuShot.lifetime = .keepAlways; add(menuShot)
        for title in ["Translate selected text", "Translate clipboard text", "Translate screen region"] {
            XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.menuItems.matching(identifier: title).allElementsBoundByIndex.contains { $0.isHittable })
        }
        app.typeKey(.escape, modifierFlags: [])
        editor.click(); app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(editor.value as? String, mainText + "\n")
        XCTAssertTrue(app.buttons["Prepare translation"].exists)
        board.clearContents(); board.setString(quickText, forType: .string)
        app.typeKey("v", modifierFlags: [.control, .shift])
        let output = app.staticTexts["text.translation.text"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            output.exists && (output.value as? String ?? output.label).lowercased().contains("библиотек") && app.buttons["text.translate"].label == "Translate"
        }, object: nil)], timeout: 120), .completed)
        XCTAssertEqual(editor.value as? String, quickText)
        XCTAssertFalse(app.dialogs["Quick translation"].exists)
        XCTAssertEqual(app.buttons["language.source"].value as? String, "en")
        XCTAssertEqual(app.buttons["language.target"].value as? String, "ru")
        XCTAssertTrue(app.buttons["text.source.playback.startStop"].isEnabled)
        XCTAssertTrue(app.buttons["text.target.playback.startStop"].isEnabled)
        XCTAssertFalse(app.staticTexts["integration.message"].exists)
        let completed = XCTAttachment(screenshot: app.windows["Kat translator"].screenshot()); completed.name = "hotkey-main-translation"; completed.lifetime = .keepAlways; add(completed)
        app.buttons["language.target"].click()
        let search = app.textFields["language.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.typeText("Deutsch")
        XCTAssertTrue(app.buttons["language.option.de"].waitForExistence(timeout: 5))
        app.buttons["language.option.de"].click()
        XCTAssertEqual(app.buttons["language.target"].value as? String, "de")
        XCTAssertFalse(app.checkBoxes["language.automatic"].exists)
        let automaticSpeech = app.checkBoxes["language.automaticSpeech"]
        XCTAssertEqual(automaticSpeech.frame.midY, app.buttons["mode.text"].frame.midY, accuracy: 3)
        app.buttons["language.source"].click()
        let auto = app.buttons["language.option.auto"]
        XCTAssertTrue(auto.waitForExistence(timeout: 5)); auto.click()
        // The next hotkey returns to the configured quick target, not the last manual direction.
        app.buttons["mode.camera"].click()
        XCTAssertTrue(app.buttons["Open image…"].waitForExistence(timeout: 10))
        app.buttons["language.source"].click()
        XCTAssertTrue(app.buttons["language.option.auto"].waitForExistence(timeout: 5))
        app.buttons["language.option.auto"].click()
        app.typeKey("v", modifierFlags: [.control, .shift])
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            editor.exists && app.buttons["language.target"].value as? String == "ru" && output.exists && (output.value as? String ?? output.label).lowercased().contains("библиотек") && app.buttons["text.translate"].label == "Translate"
        }, object: nil)], timeout: 120), .completed)
        XCTAssertFalse(app.dialogs["Quick translation"].exists)
        XCTAssertEqual(app.buttons["language.source"].value as? String, "auto:en")
        XCTAssertEqual(board.string(forType: .string), quickText)
        app.buttons["Settings"].firstMatch.click(); app.buttons["settings.shortcuts"].click()
        app.buttons["shortcuts.reset"].click()
        XCTAssertEqual(app.buttons["shortcuts.record.submit"].label, "Enter")
        for (action, label) in [("selectedText", "⌥1"), ("screenRegion", "⌥2"), ("clipboardText", "⌥3")] {
            XCTAssertEqual(app.buttons["shortcuts.record." + action].label, label)
        }
        app.buttons["settings.close"].click()
    }
    @MainActor func testEnterTranslatesAndShiftEnterInsertsNewline() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["KAT_SHORTCUTS_TEST_SUITE"] = "kat-enter-ui-" + UUID().uuidString
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-ApplePersistenceIgnoreState", "YES", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        let firstLine = "The library opens at nine."
        let secondLine = "Please bring your library card."
        defer {
            app.terminate()
            if [firstLine, secondLine].contains(board.string(forType: .string) ?? "") {
                board.clearContents(); board.writeObjects(saved)
            }
        }
        func paste(_ text: String) {
            board.clearContents(); board.setString(text, forType: .string)
            app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        }
        app.launch()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30)); app.buttons["mode.text"].click()
        let editor = app.textViews["Original text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["text.submit.hint"].exists)
        editor.click(); paste(firstLine)
        app.typeKey(.return, modifierFlags: .shift)
        XCTAssertEqual(editor.value as? String, firstLine + "\n")
        XCTAssertTrue(app.buttons["Prepare translation"].exists)
        paste(secondLine)
        let source = firstLine + "\n" + secondLine
        XCTAssertEqual(editor.value as? String, source)
        // Enter shares the button's preparation action until the model is ready.
        app.typeKey(.return, modifierFlags: [])
        let translate = app.buttons["text.translate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Translate' AND enabled == true"), object: translate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        XCTAssertEqual(editor.value as? String, source)
        editor.click(); app.typeKey(.return, modifierFlags: [])
        let output = app.staticTexts["text.translation.text"]
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard output.exists else { return false }
            return (output.value as? String ?? output.label).lowercased().contains("библиотек")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [translated], timeout: 60), .completed)
        XCTAssertEqual(editor.value as? String, source)
        XCTAssertTrue(app.buttons["text.copy.target"].isEnabled)
        let window = app.windows.firstMatch
        let right = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -1, dy: 0))
        right.click(forDuration: 0.2, thenDragTo: right.withOffset(CGVector(dx: 780 - window.frame.width, dy: 0)))
        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.name = "enter-translation-compact"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(window.frame.contains(app.staticTexts["text.submit.hint"].frame))
        app.buttons["text.clear.source"].click()
        XCTAssertFalse(translate.isEnabled)
        editor.click(); app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertFalse(translate.isEnabled)
    }
    @MainActor func testModelLanguageListsMatchPickerSupport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer {
            app.terminate()
            if board.string(forType: .string) == "Balinese" { board.clearContents(); board.writeObjects(saved) }
        }
        func enterQuery(_ field: XCUIElement) {
            field.click()
            board.clearContents(); board.setString("Balinese", forType: .string)
            app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
            XCTAssertEqual(field.value as? String, "Balinese")
        }
        for (model, count) in [("index-translate-9b-q4km", 150)] {
            app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-selectedTranslationModel", model, "-translationSource", "ru", "-translationTarget", "en", "-favoriteTranslationLanguages", "ban,id,ru,uk"]
            app.launch()
            XCTAssertTrue(app.buttons["language.target"].waitForExistence(timeout: 60))
            app.buttons["language.target"].click()
            XCTAssertTrue(app.buttons["language.option.ru"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.buttons["language.option.ban"].exists, count == 152, "Unsupported favorites must be hidden")
            XCTAssertEqual(app.buttons["language.option.id"].exists, count != 14)
            XCTAssertEqual(app.buttons["language.option.uk"].exists, count == 150 || count == 152)
            let search = app.textFields["language.search"]
            enterQuery(search)
            if count == 152 { XCTAssertTrue(app.buttons["language.option.ban"].waitForExistence(timeout: 5)) }
            else {
                XCTAssertTrue(app.staticTexts["Language not found"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["language.option.ban"].exists)
            }
            app.buttons["language.close"].click()
            app.buttons["Models"].firstMatch.click()
            let info = app.buttons["model.info." + model]
            XCTAssertTrue(info.waitForExistence(timeout: 10)); info.click()
            let link = app.buttons["model.languages.open"]
            XCTAssertTrue(link.waitForExistence(timeout: 10))
            link.click()
            XCTAssertTrue(app.staticTexts["model.languages.count"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["model.languages.count"].value as? String ?? app.staticTexts["model.languages.count"].label, "Translation languages in the app: \(count)")
            let listShot = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot())
            listShot.name = "model-languages-list-" + model; listShot.lifetime = .keepAlways; add(listShot)
            let infoSearch = app.textFields["model.languages.search"]
            enterQuery(infoSearch)
            let row = app.descendants(matching: .any).matching(identifier: "model.languages.row.ban").firstMatch
            if count == 152 { XCTAssertTrue(row.waitForExistence(timeout: 5)) }
            else { XCTAssertTrue(app.staticTexts["Language not found"].waitForExistence(timeout: 5)); XCTAssertFalse(row.exists) }
            let shot = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot())
            shot.name = "model-languages-" + model; shot.lifetime = .keepAlways; add(shot)
            app.buttons["model.info.close"].click()
            app.buttons["models.close"].click()
            XCTAssertEqual(app.buttons["language.target"].value as? String, "en")
            app.terminate()
        }
    }
    @MainActor func testCenteredProcessingOverlayCancelsAndRevealsResult() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-macExperimentalTranslationChunks", "NO", "-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-ApplePersistenceIgnoreState", "YES", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30)); app.buttons["mode.text"].click()
        let text = "The library opens at nine in the morning. Visitors can read books, use the computers, and ask the staff for help. On Saturday, children and their parents meet in the large room upstairs to discuss stories. Please bring your library card if you want to borrow a book. The cafe across the street serves tea and fresh bread. After the meeting, we will walk through the park and take the bus home."
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { if board.string(forType: .string) == text { board.clearContents(); board.writeObjects(saved) } }
        let editor = app.textViews["Original text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.click()
        board.clearContents(); board.setString(text, forType: .string)
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        app.buttons["Prepare translation"].click()
        let translate = app.buttons["text.translate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Translate' AND enabled == true"), object: translate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        translate.click()
        let cancel = app.buttons["processing.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); XCTAssertTrue(cancel.isEnabled)
        XCTAssertEqual(cancel.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 3)
        let loading = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); loading.name = "centered-processing-mac"; loading.lifetime = .keepAlways; add(loading)
        cancel.click()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 15))
        // NSTextView's AX enabled flag is unreliable; verify actual editing instead.
        editor.click()
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Select All"].click()
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        XCTAssertEqual(editor.value as? String, text)
        translate.click()
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 90))
        XCTAssertTrue(app.buttons["text.copy.target"].isEnabled)
        let output = app.staticTexts["text.translation.text"]
        let result = output.value as? String ?? output.label
        XCTAssertTrue(result.lowercased().contains("библиотек"), result)
        let completed = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); completed.name = "processing-result-mac"; completed.lifetime = .keepAlways; add(completed)
    }
    @MainActor func testAutomaticTextKeepsSelectedTarget() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-ApplePersistenceIgnoreState", "YES", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "fr", "-automaticLanguage", "YES", "-automaticSpeechText", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30)); app.buttons["mode.text"].click()
        XCTAssertTrue(app.buttons["language.source"].waitForExistence(timeout: 90))
        app.buttons["Models"].firstMatch.click()
        let automaticModel = app.buttons["model.select.auto"]
        XCTAssertTrue(automaticModel.waitForExistence(timeout: 15)); automaticModel.click()
        app.buttons["models.close"].click()
        XCTAssertTrue(app.buttons["language.source"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["language.source"].value as? String, "auto")
        XCTAssertEqual(app.buttons["language.target"].value as? String, "fr")
        let text = "Where is the train station? I would like to buy a ticket for tomorrow."
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { if board.string(forType: .string) == text { board.clearContents(); board.writeObjects(saved) } }
        let editor = app.textViews["Original text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.click()
        board.clearContents(); board.setString(text, forType: .string)
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        XCTAssertEqual(editor.value as? String, text)
        app.buttons["Prepare translation"].click()
        let translate = app.buttons["text.translate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Translate' AND enabled == true"), object: translate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed); translate.click()
        let result = app.staticTexts["text.translation.text"]
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let output = result.value as? String ?? result.label
            return output.lowercased().contains("gare")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [translated], timeout: 60), .completed)
        XCTAssertEqual(app.buttons["language.target"].value as? String, "fr")
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = "automatic-en-fr"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testAudioFilePickerAndImport() throws {
        continueAfterFailure = false
        executionTimeAllowance = 600
        let environment = ProcessInfo.processInfo.environment
        let userFile = environment["KAT_AUDIO_FILE"]
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let filePath = userFile ?? root.appendingPathComponent(".build/audio-import/import-voice.mp3").path
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { if board.string(forType: .string) == filePath { board.clearContents(); board.writeObjects(saved) } }
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-ApplePersistenceIgnoreState", "YES", "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", userFile == nil ? "en" : "ru", "-translationTarget", userFile == nil ? "ru" : "en", "-automaticLanguage", "NO", "-automaticSpeechVoice", "NO", "-memorySaving", "NO", "-historyRecordText", userFile == nil ? "NO" : "YES", "-historyRecordAudio", "NO"]
        app.launch(); defer { app.terminate() }
        let button = app.buttons["voice.import"]
        let prepare = app.buttons["Prepare translation"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 60)); XCTAssertFalse(button.exists)
        prepare.click()
        XCTAssertTrue(button.waitForExistence(timeout: 90)); XCTAssertTrue(button.isHittable)
        button.click()
        let cancel = app.buttons["CancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.click()
        XCTAssertTrue(button.isHittable)
        button.click()
        app.sheets["open-panel"].typeKey("/", modifierFlags: [])
        let path = app.textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 10)); path.click()
        board.clearContents(); board.setString(filePath, forType: .string)
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Select All"].click()
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        XCTAssertEqual(path.value as? String, filePath)
        app.typeKey(.return, modifierFlags: [])
        let open = app.buttons["OKButton"]
        let selectable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [selectable], timeout: 10), .completed)
        let started = Date()
        open.click()
        XCTAssertTrue(app.buttons["voice.translation.expand"].waitForExistence(timeout: 480))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in app.buttons["voice.import"].isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 30), .completed)
        let source = app.staticTexts["voice.original.text"].value as? String ?? app.staticTexts["voice.original.text"].label
        let target = app.staticTexts["voice.translation.text"].value as? String ?? app.staticTexts["voice.translation.text"].label
        XCTAssertFalse(source.isEmpty); XCTAssertFalse(target.isEmpty)
        if userFile == nil { XCTAssertTrue(source.lowercased().contains("tea")); XCTAssertTrue(target.lowercased().contains("ча")) }
        if let report = environment["KAT_AUDIO_REPORT"] {
            let row: [String: Any] = ["original": source, "translation": target, "wallSeconds": Date().timeIntervalSince(started), "file": filePath]
            try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: report))
        }
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = "audio-import-mac"; shot.lifetime = .keepAlways; add(shot)
    }
    func testNewsTranslationKeepsOnePartAndShowsTiming() throws {
        guard ProcessInfo.processInfo.environment["KAT_RUN_OUTPUT_BUDGET_UI"] == "1" else { throw XCTSkip("Opt-in real Index news UI check") }
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try String(contentsOf: root.appendingPathComponent("tests/fixtures/translation-output-limit-ru.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en", "-showTechnicalInfo", "YES",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "ru", "-translationTarget", "en", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-memorySaving", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30)); app.buttons["mode.text"].click()
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { if board.string(forType: .string) == fixture { board.clearContents(); board.writeObjects(saved) } }
        board.clearContents(); board.setString(fixture, forType: .string)
        let editor = app.textViews["Original text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.click()
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        XCTAssertEqual(editor.value as? String, fixture)
        if app.buttons["Prepare translation"].exists { app.buttons["Prepare translation"].click() }
        let translate = app.buttons["text.translate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Translate' AND enabled == true"), object: translate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        translate.click()
        let progress = app.staticTexts["Translating part 1 of 1"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        let timing = app.staticTexts["text.timing"]
        var retried = false
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if app.staticTexts["Translating part 1 of 2"].exists || app.staticTexts["Translating part 2 of 2"].exists { retried = true }
            return timing.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertFalse(retried)
        XCTAssertFalse(progress.exists)
        let output = app.staticTexts["text.translation.text"]
        let text = output.label.isEmpty ? output.value as? String ?? "" : output.label
        XCTAssertGreaterThan(text.count, 2500)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "news-one-part-result"; shot.lifetime = .keepAlways; add(shot)
    }
    func testTranslationTimingFollowsDiagnosticsAndResult() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "ru", "-translationTarget", "en", "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-memorySaving", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30))
        let diagnosticsWereVisible = app.buttons["toolbar.diagnostics"].exists
        func setDiagnostics(_ visible: Bool) {
            guard app.buttons["toolbar.diagnostics"].exists != visible else { return }
            app.buttons["Settings"].firstMatch.click()
            let toggle = app.switches["settings.showTechnicalInfo"]
            for _ in 0..<12 where !toggle.isHittable { app.sheets.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -650) }
            XCTAssertTrue(toggle.isHittable)
            print("DIAGNOSTICS_TOGGLE", toggle.debugDescription)
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).click()
            app.buttons["settings.close"].click()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == %@", NSNumber(value: visible)), object: app.buttons["toolbar.diagnostics"])
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }
        defer { setDiagnostics(diagnosticsWereVisible); app.terminate() }
        setDiagnostics(true)
        app.buttons["mode.text"].click()
        let timing = app.staticTexts["text.timing"]
        XCTAssertFalse(timing.exists)
        let fixture = "Пожалуйста, принесите стакан воды без сахара."
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { if board.string(forType: .string) == fixture { board.clearContents(); board.writeObjects(saved) } }
        board.clearContents(); board.setString(fixture, forType: .string)
        let editor = app.textViews["Original text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.click()
        app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        XCTAssertEqual(editor.value as? String, fixture)
        if app.buttons["Prepare translation"].exists { app.buttons["Prepare translation"].click() }
        let translate = app.buttons["text.translate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Translate' AND enabled == true"), object: translate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        translate.click()
        XCTAssertTrue(timing.waitForExistence(timeout: 60))
        let value = timing.label.isEmpty ? timing.value as? String ?? "" : timing.label
        XCTAssertTrue(value.hasPrefix("Translation: "))
        XCTAssertFalse(value.contains("Recognition"))
        XCTAssertTrue(app.buttons["text.copy.target"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "translation-timing-mac"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["mode.voice"].click()
        XCTAssertFalse(app.staticTexts["voice.timing"].exists)
        app.buttons["mode.text"].click(); XCTAssertTrue(timing.exists)
        setDiagnostics(false)
        XCTAssertFalse(timing.exists)
        XCTAssertFalse(app.buttons["toolbar.diagnostics"].exists)
        XCTAssertTrue(app.buttons["text.copy.target"].isEnabled)
        app.buttons["text.clear.source"].click()
        XCTAssertFalse(timing.exists)
    }
    /// Opt-in real-model check: partial output stays accessible while the cancel action is visible.
    func testInlinePartialTranslation() throws {
        guard let path = ProcessInfo.processInfo.environment["KAT_INLINE_APP"] else {
            throw XCTSkip("Requires an explicit local app and installed Index 9B model")
        }
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
            "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "en", "-translationTarget", "ru",
            "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-memorySaving", "NO",
            "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30))
        app.buttons["mode.text"].click()
        let editor = app.textViews["Original text"].exists ? app.textViews["Original text"] : app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let fixture = Array(repeating: "The library will open at nine tomorrow. Please return the books to the front desk before Friday. Our visitors can read newspapers in the quiet room and ask the librarian for help.", count: 12).joined(separator: "\n\n")
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { if board.string(forType: .string) == fixture { board.clearContents(); board.writeObjects(saved) } }
        board.clearContents(); XCTAssertTrue(board.setString(fixture, forType: .string))
        editor.click(); app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
        XCTAssertEqual(editor.value as? String, fixture)
        if app.buttons["Prepare translation"].exists { app.buttons["Prepare translation"].click() }
        let translate = app.buttons["text.translate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Translate' AND enabled == true"), object: translate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        translate.click()
        let cancel = app.buttons["translation.inline.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["translation.partial.notice"].waitForExistence(timeout: 30))
        XCTAssertTrue(cancel.isHittable)
        XCTAssertFalse(app.otherElements["processing.overlay"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "text.processing.cat").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["text.translation.text"].exists)
        XCTAssertTrue(app.staticTexts["text.translation.text"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "inline-partial-translation"; shot.lifetime = .keepAlways; add(shot)
        cancel.click()
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts["translation.partial.notice"].exists)
    }

    /// Opt-in comparison against a packaged binary, without rebuilding or replacing that app.
    func testArchivedBuildArticleBenchmark() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["KAT_BENCHMARK_APP"] else { throw XCTSkip("Requires an archived app path") }
        continueAfterFailure = false
        executionTimeAllowance = 600
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/long-context/build17")
        let appURL = URL(fileURLWithPath: path)
        let bundle = try XCTUnwrap(Bundle(url: appURL))
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, "17")
        let fixture = try String(contentsOf: root.appendingPathComponent("tests/fixtures/context-comparison-yandex-ru.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let trace = directory.appendingPathComponent("memory.jsonl")
        let app = XCUIApplication(url: appURL)
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO",
            "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-translationSource", "ru", "-translationTarget", "en",
            "-automaticLanguage", "NO", "-automaticSpeechText", "NO", "-memorySaving", "NO",
            "-historyRecordText", "NO", "-historyRecordAudio", "NO", "-historyRecordImages", "NO"]
        app.launchEnvironment = ["OT_MT_MEMORY_TRACE": "1", "OT_MT_MEMORY_TRACE_PATH": trace.path]
        app.launch(); defer { app.terminate() }
        let process = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "org.openoffline.translator.mac").first)
        XCTAssertEqual(process.bundleURL?.standardizedFileURL, appURL.standardizedFileURL)
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30)); app.buttons["mode.text"].click()
        let editor = app.textViews["Original text"].exists ? app.textViews["Original text"] : app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let value = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { value.setData(data, forType: type) } }
            return value
        }
        let warmup = "Проверка готовности модели перевода."
        defer {
            if [fixture, warmup].contains(board.string(forType: .string) ?? "") {
                board.clearContents(); board.writeObjects(saved)
            }
        }
        func paste(_ text: String) {
            board.clearContents(); XCTAssertTrue(board.setString(text, forType: .string))
            // Use the app's clear action: simulated Cmd+A depends on the active keyboard layout.
            if let value = editor.value as? String, !value.isEmpty { app.buttons["text.clear.source"].click() }
            editor.click()
            app.menuBars.menuBarItems["Edit"].click(); app.menuItems["Paste"].click()
            let entered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: editor)
            XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 5), .completed)
        }
        paste(warmup)
        let prepare = app.buttons["Prepare translation"]
        if prepare.exists { prepare.click() }
        let translate = app.buttons["text.translate"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Translate' AND enabled == true"), object: translate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed)
        translate.click()
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["text.copy.target"])
        XCTAssertEqual(XCTWaiter.wait(for: [translated], timeout: 90), .completed)
        paste(fixture)
        var rows: [[String: Any]] = []
        for run in 1...2 {
            let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
            let started = Date().timeIntervalSince1970
            translate.click()
            let progress = app.descendants(matching: .any).matching(identifier: "translation.progress").firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: 15))
            let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 180), .completed)
            let finished = Date().timeIntervalSince1970
            XCTAssertTrue(app.buttons["text.copy.target"].isEnabled)
            let resultText = app.staticTexts["text.translation.text"]
            let output = resultText.label.isEmpty ? (resultText.value as? String ?? "") : resultText.label
            rows.append(["run": run, "startedAt": started, "finishedAt": finished,
                "uiWallSeconds": finished - started, "translation": output,
                "thermalBefore": thermalBefore, "thermalAfter": ProcessInfo.processInfo.thermalState.rawValue])
            let report: [String: Any] = ["build": "17", "appPath": path, "pid": process.processIdentifier,
                "model": "index-translate-9b-q4km", "source": fixture, "sourceCharacters": fixture.count, "rows": rows]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "build17-results-run-\(run)"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertGreaterThan(output.count, 1500)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "build17-article-\(run)"; shot.lifetime = .keepAlways; add(shot)
        }
    }
    func testSettingsAndModelsOpenFromImageTab() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["mode.camera"].waitForExistence(timeout: 30))
        for _ in 0..<2 {
            app.buttons["mode.camera"].click()
            XCTAssertTrue(app.buttons["Open image…"].waitForExistence(timeout: 5))
            for (title, closeID) in [("Settings", "settings.close"), ("Models", "models.close"), ("Translation history", "history.close")] {
                let button = app.buttons[title].firstMatch
                XCTAssertTrue(button.isEnabled, "\(title) must be available in idle Image mode")
                button.click()
                let close = app.buttons[closeID]
                XCTAssertTrue(close.waitForExistence(timeout: 5))
                close.click()
                XCTAssertTrue(app.buttons["Open image…"].waitForExistence(timeout: 5))
            }
            app.buttons["mode.text"].click()
            XCTAssertTrue(app.buttons["text.source.expand"].waitForExistence(timeout: 5))
        }
    }
    func testHistoryOpensFromImageTab() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["mode.camera"].waitForExistence(timeout: 30))
        app.buttons["mode.camera"].click()
        XCTAssertTrue(app.buttons["Open image…"].waitForExistence(timeout: 5))
        let history = app.buttons["toolbar.history"]
        XCTAssertTrue(history.isEnabled)
        history.click()
        let close = app.buttons["history.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.click()
        XCTAssertTrue(app.buttons["Open image…"].waitForExistence(timeout: 5))
        app.buttons["mode.text"].click()
        XCTAssertTrue(app.buttons["text.source.expand"].waitForExistence(timeout: 5))
    }
    func testFullscreenReaderAndCharacterCounts() {
        continueAfterFailure = false
        func displayedText(_ element: XCUIElement) -> String {
            element.label.isEmpty ? (element.value as? String ?? "") : element.label
        }
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en", "-showTechnicalInfo", "NO"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["mode.text"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["model.current"].exists)
        app.buttons["mode.text"].click()
        let expand = app.buttons["text.source.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); XCTAssertFalse(expand.isEnabled)
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let value = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { value.setData(data, forType: type) } }
            return value
        }
        let fixture = "Hello, world!\nReading a translation should be comfortable. Привет 🐈!"
        board.clearContents(); XCTAssertTrue(board.setString(fixture, forType: .string))
        defer { if board.string(forType: .string) == fixture { board.clearContents(); board.writeObjects(saved) } }
        let editor = app.textViews["Text original"].exists ? app.textViews["Text original"] : app.textViews.firstMatch
        editor.click()
        app.menuBars.menuBarItems["Edit"].click()
        app.menuItems["Paste"].click()
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", fixture), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 5), .completed)
        XCTAssertTrue(expand.isEnabled)
        XCTAssertLessThan(app.buttons["text.translate"].frame.maxY, editor.frame.minY)
        XCTAssertEqual(displayedText(app.staticTexts["text.source.count"]), "Characters: \(fixture.count)")
        XCTAssertLessThanOrEqual(expand.frame.maxX, app.buttons["text.source.playback.speed"].frame.minX)
        expand.click()
        let close = app.buttons["reader.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(displayedText(app.staticTexts["reader.text"]), fixture)
        XCTAssertEqual(displayedText(app.staticTexts["reader.count"]), "Characters: \(fixture.count)")
        XCTAssertGreaterThan(app.scrollViews["reader.scroll"].frame.width, app.windows.firstMatch.frame.width * 0.9)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "fullscreen-text-reader-mac"; shot.lifetime = .keepAlways; add(shot)
        close.click()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, fixture)
    }
    func testDesktopDiagnosticsAndPanelSurfaces() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en", "-showTechnicalInfo", "YES"]
        app.launch()
        defer { app.terminate() }
        let diagnostics = app.buttons["toolbar.diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["model.current"].exists)
        diagnostics.click()
        let memory = app.descendants(matching: .any).matching(identifier: "diagnostics.memory").firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 5))
        XCTAssertTrue(memory.label.hasPrefix("App memory (footprint): "))
        XCTAssertFalse(app.staticTexts["Total iPhone CPU"].exists)
        XCTAssertFalse(app.staticTexts["RAM: iOS accounting"].exists)
        XCTAssertFalse(app.staticTexts["Still available to the app"].exists)
        let cpu = app.descendants(matching: .any).matching(identifier: "diagnostics.cpu.system").firstMatch
        XCTAssertTrue(cpu.exists)
        let sampled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            cpu.label.contains("%")
        }, object: cpu)
        XCTAssertEqual(XCTWaiter.wait(for: [sampled], timeout: 5), .completed)
        func shot(_ name: String) {
            let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
        }
        shot("diagnostics-desktop")
        app.buttons["diagnostics.close"].click()
        for (title, close) in [("Settings", "settings.close"), ("Models", "models.close"), ("Translation history", "history.close")] {
            app.buttons[title].firstMatch.click()
            XCTAssertTrue(app.buttons[close].waitForExistence(timeout: 5))
            shot("panel-" + close)
            app.buttons[close].click()
        }
    }
    func testInAppLanguageChangesImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons.matching(NSPredicate(format: "label == 'Settings' OR label == 'Настройки'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.click()
        let picker = app.popUpButtons["settings.interfaceLanguage"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let original = picker.value as? String ?? "System default"
        func choose(_ english: String, _ russian: String) {
            picker.click()
            let option = app.menuItems[english]
            if option.exists { option.click() } else { app.menuItems[russian].click() }
        }
        choose("Russian", "Русский")
        XCTAssertTrue(app.staticTexts["Управление записью"].waitForExistence(timeout: 5))
        app.buttons["settings.close"].click()
        XCTAssertEqual(app.buttons["mode.voice"].label, "Голос")
        app.buttons["Настройки"].firstMatch.click()
        choose("English", "English")
        XCTAssertTrue(app.staticTexts["Recording controls"].waitForExistence(timeout: 5))
        app.buttons["settings.close"].click()
        XCTAssertEqual(app.buttons["mode.voice"].label, "Voice")
        app.buttons["Settings"].firstMatch.click()
        if original == "Russian" || original == "Русский" { choose("Russian", "Русский") }
        else if original != "English" { choose("System default", "Как в системе") }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "settings-language"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["settings.close"].click()
    }
    func testCopyVersionInformation() {
        let app = XCUIApplication()
        app.launchArguments = ["-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons.matching(NSPredicate(format: "label == 'Settings' OR label == 'Настройки'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 20)); settings.click()
        let copy = app.buttons["settings.copyVersion"]
        for _ in 0..<8 {
            if copy.isHittable { break }
            app.sheets.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -650)
        }
        XCTAssertTrue(copy.isHittable)
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let value = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { value.setData(data, forType: type) } }
            return value
        }
        copy.click()
        let copied = board.string(forType: .string) ?? ""
        XCTAssertTrue(copied.hasPrefix("Kat translator\n"))
        XCTAssertTrue(copied.contains("0.1.0"))
        XCTAssertTrue(copied.contains("Build: 15") || copied.contains("Сборка: 15"))
        XCTAssertNotNil(copied.range(of: "mac-[0-9a-f]{16}", options: .regularExpression))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "settings-build-id"; shot.lifetime = .keepAlways; add(shot)
        // A second tap should copy too; restore the user's clipboard after the check.
        copy.click()
        XCTAssertEqual(board.string(forType: .string), copied)
        if board.string(forType: .string) == copied { board.clearContents(); board.writeObjects(saved) }
        app.buttons["settings.close"].click()
    }
    func testCenteredModelPreparation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en"]
        for targetWidth: CGFloat in [1600, 820] {
            app.launch()
            let prepare = app.buttons["Prepare translation"]
            XCTAssertTrue(prepare.waitForExistence(timeout: 30))
            let window = app.windows.firstMatch
            let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0))
            edge.click(forDuration: 0.2, thenDragTo: edge.withOffset(CGVector(dx: targetWidth - window.frame.width, dy: 0)))
            prepare.click()
            let title = app.staticTexts["Preparing models"]
            // Warm cached models can finish before XCTest's first one-second poll.
            // Exact sizing and drawing bounds are covered by deterministic render tests.
            if title.waitForExistence(timeout: 2) {
                let panel = app.descendants(matching: .any).matching(identifier: "models.preparation").firstMatch
                if panel.exists && !app.buttons["voice.record"].exists {
                    XCTAssertEqual(title.frame.midX, window.frame.midX, accuracy: 4)
                    XCTAssertGreaterThan(panel.frame.width, 700)
                    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "preparation-width-\(Int(targetWidth))"; shot.lifetime = .keepAlways; add(shot)
                }
            }
            app.buttons["mode.text"].click()
            app.buttons["mode.voice"].click()
            XCTAssertTrue(app.buttons["voice.record"].waitForExistence(timeout: 90))
            let ready = XCTAttachment(screenshot: window.screenshot())
            ready.name = "voice-actions-width-\(Int(targetWidth))"; ready.lifetime = .keepAlways; add(ready)
            app.terminate()
        }
    }
    func testCenteredVoiceWorkspace() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-ApplePersistenceIgnoreState", "YES", "-appInterfaceLanguage", "en", "-recordingMode", "toggle", "-recordingSilenceSeconds", "30", "-automaticSpeechVoice", "NO", "-historyRecordText", "NO", "-historyRecordAudio", "NO"]
        app.launch()
        defer { app.terminate() }
        let prepare = app.buttons["Prepare translation"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 30)); prepare.click()
        let record = app.buttons["voice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 90))
        let window = app.windows.firstMatch
        let importAudio = app.buttons["voice.import"]
        XCTAssertTrue(importAudio.exists)
        XCTAssertEqual((importAudio.frame.minX + record.frame.maxX) / 2, window.frame.midX, accuracy: 4)
        XCTAssertEqual(importAudio.frame.size, record.frame.size)
        XCTAssertGreaterThanOrEqual(record.frame.width, 80)
        XCTAssertLessThanOrEqual(record.frame.width, 144)
        XCTAssertLessThan(record.frame.maxY, window.frame.maxY - 80)
        XCTAssertFalse(app.staticTexts["Tap to record"].exists)
        func shot(_ name: String) {
            let capture = XCTAttachment(screenshot: window.screenshot()); capture.name = name; capture.lifetime = .keepAlways; add(capture)
        }
        shot("voice-centered-ready")
        func resize(width: CGFloat? = nil, height: CGFloat? = nil) {
            let before = window.frame
            let desired = CGSize(width: width ?? before.width, height: height ?? before.height)
            // Resize from the top-left: the bottom edge of a filled window is at the display boundary.
            let corner = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 1, dy: 1))
            corner.click(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: before.width - desired.width, dy: before.height - desired.height)))
            XCTAssertEqual(window.frame.width, desired.width, accuracy: 3)
            XCTAssertEqual(window.frame.height, desired.height, accuracy: 3)
            XCTAssertEqual(importAudio.frame.size, record.frame.size)
            XCTAssertEqual(importAudio.frame.midY, record.frame.midY, accuracy: 1)
            XCTAssertEqual((importAudio.frame.minX + record.frame.maxX) / 2, window.frame.midX, accuracy: 4)
        }
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0)).withOffset(CGVector(dx: 0, dy: 20)).doubleClick()
        let largeWindow = window.frame
        let largeDiameter = record.frame.width
        shot("voice-adaptive-large")
        resize(height: 740)
        XCTAssertLessThan(record.frame.width, largeDiameter)
        shot("voice-adaptive-short")
        resize(height: largeWindow.height)
        resize(width: 800)
        XCTAssertLessThan(record.frame.width, largeDiameter)
        shot("voice-adaptive-narrow")
        resize(height: 740)
        XCTAssertGreaterThanOrEqual(record.frame.width, 80)
        shot("voice-adaptive-small")
        record.click()
        let pause = app.buttons["voice.pauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 30))
        XCTAssertEqual(record.label, "Finish recording")
        XCTAssertEqual(record.frame.midX, window.frame.midX, accuracy: 4)
        shot("voice-centered-recording")
        pause.click()
        XCTAssertEqual(pause.label, "Resume recording")
        pause.click()
        record.click()
        shot("voice-centered-processing")
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: settings)], timeout: 90), .completed)
        XCTAssertTrue(record.exists)
        shot("voice-centered-finished")
        app.buttons["mode.text"].click()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        app.buttons["mode.voice"].click()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
    }
    func testDesktopWindows() {
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-AppleLanguages", "(ru)"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        let models = app.buttons["Модели"]
        XCTAssertTrue(models.waitForExistence(timeout: 10)); models.click()
        XCTAssertTrue(app.buttons["Настроить языки и загрузку"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "mac-models"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["models.close"].click()
        app.buttons["Настройки"].firstMatch.click()
        XCTAssertTrue(app.buttons["settings.recognition.whisper"].waitForExistence(timeout: 10))
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "mac-settings"; settings.lifetime = .keepAlways; add(settings)
        app.buttons["settings.close"].click()
        let text = app.buttons["Текст"]
        if text.exists { text.click() } else { app.radioButtons["Текст"].click() }
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
        app.textViews.firstMatch.click(); app.textViews.firstMatch.typeText("A short desktop text.")
        let main = XCTAttachment(screenshot: app.screenshot()); main.name = "mac-text"; main.lifetime = .keepAlways; add(main)
        app.buttons["text.copy.source"].click()
        app.buttons["text.clear.source"].click()
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "")
        app.terminate()
    }
    func testDesktopPanelGeometry() {
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 25))
        app.buttons["Text"].click()
        func body(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        let source = body("text.source.body"), target = body("text.target.body")
        XCTAssertTrue(source.waitForExistence(timeout: 10)); XCTAssertTrue(target.exists)
        func checkPanels(_ name: String) {
            XCTAssertEqual(source.frame.minY, target.frame.minY, accuracy: 1)
            XCTAssertEqual(source.frame.maxY, target.frame.maxY, accuracy: 1)
            let shot = XCTAttachment(screenshot: window.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        checkPanels("text-aligned-wide")
        let frame = window.frame
        let right = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0))
        right.click(forDuration: 0.2, thenDragTo: right.withOffset(CGVector(dx: 820 - frame.width, dy: 0)))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 3))
        bottom.click(forDuration: 0.2, thenDragTo: bottom.withOffset(CGVector(dx: 0, dy: 740 - window.frame.height)))
        XCTAssertLessThanOrEqual(window.frame.width, 840)
        checkPanels("text-aligned-small")
        // Native title-bar zoom must use the screen, not the minimum content size.
        let compactFrame = window.frame
        let screenTop = NSScreen.screens.first!.frame.maxY
        let screenFrames = NSScreen.screens.map { screen in
            CGRect(x: screen.visibleFrame.minX, y: screenTop - screen.visibleFrame.maxY,
                   width: screen.visibleFrame.width, height: screen.visibleFrame.height)
        }
        let screenFrame = screenFrames.max {
            $0.intersection(compactFrame).width * $0.intersection(compactFrame).height <
            $1.intersection(compactFrame).width * $1.intersection(compactFrame).height
        }!
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0)).withOffset(CGVector(dx: 0, dy: 20)).doubleClick()
        XCTAssertEqual(window.frame.width, screenFrame.width, accuracy: 2)
        XCTAssertEqual(window.frame.height, screenFrame.height, accuracy: 2)
        XCTAssertEqual(window.frame.minX, screenFrame.minX, accuracy: 2)
        XCTAssertEqual(window.frame.minY, screenFrame.minY, accuracy: 2)
        checkPanels("text-zoomed")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0)).withOffset(CGVector(dx: 0, dy: 20)).doubleClick()
        XCTAssertEqual(window.frame.width, compactFrame.width, accuracy: 2)
        XCTAssertEqual(window.frame.height, compactFrame.height, accuracy: 2)
        XCTAssertEqual(window.frame.minX, compactFrame.minX, accuracy: 2)
        XCTAssertEqual(window.frame.minY, compactFrame.minY, accuracy: 2)
        app.buttons["Image"].click()
        let open = app.buttons["Open image…"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        for label in ["Open image…", "Paste image", "Save translation…", "Clear image"] {
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.exists, label)
            XCTAssertTrue(window.frame.contains(button.frame), label)
        }
        XCTAssertEqual(app.sheets.count, 0)
        let divider = body("image.divider")
        XCTAssertTrue(divider.exists)
        XCTAssertEqual(divider.frame.midX, window.frame.midX, accuracy: 1)
        divider.hover()
        let image = XCTAttachment(screenshot: window.screenshot()); image.name = "image-inline-small"; image.lifetime = .keepAlways; add(image)
        let initialX = divider.frame.midX
        func dragDivider(by distance: CGFloat) {
            let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.click(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)))
        }
        dragDivider(by: -70)
        XCTAssertLessThan(divider.frame.midX, initialX - 40)
        dragDivider(by: 140)
        XCTAssertGreaterThan(divider.frame.midX, initialX + 40)
        dragDivider(by: initialX - divider.frame.midX)
        XCTAssertEqual(divider.frame.midX, initialX, accuracy: 3)
        open.hover()
        app.buttons["mode.text"].click()
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        app.terminate()
    }

    func testDesktopPolish() {
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        func shot(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        app.buttons["Image"].click()
        XCTAssertTrue(app.buttons["Open image…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open image…"].isEnabled, "Empty Image tab must accept a file without loading Index")
        let divider = app.descendants(matching: .any).matching(identifier: "image.divider").firstMatch
        XCTAssertTrue(divider.exists)
        let x = divider.frame.midX
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -90, dy: 0)))
        XCTAssertLessThan(divider.frame.midX, x - 60, "Divider must move before an image is inserted")
        shot("image-empty-resized")
        for _ in 0..<3 {
            app.buttons["Voice"].click()
            app.buttons["Text"].click()
            XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))
            app.buttons["Image"].click()
            XCTAssertTrue(app.buttons["Open image…"].isEnabled)
        }
        app.buttons["mode.text"].click()
        app.buttons["Settings"].firstMatch.click()
        XCTAssertTrue(app.buttons["settings.close"].waitForExistence(timeout: 5))
        shot("settings-top")
        let count = app.textFields["settings.textCount"]
        count.click()
        XCTAssertGreaterThan(count.frame.width, 75)
        XCTAssertLessThan(count.frame.height, 40)
        shot("settings-retention")
        app.buttons["Voices and samples"].click()
        XCTAssertTrue(app.buttons["settings.close"].exists, "Nested voice page must keep its close control")
        shot("settings-voices-close")
        app.buttons["settings.close"].click()
        app.buttons["Models"].firstMatch.click()
        XCTAssertTrue(app.buttons["models.close"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model.info.")).firstMatch.click()
        XCTAssertTrue(app.buttons["model.info.close"].waitForExistence(timeout: 5))
        app.buttons["model.info.close"].click()
        app.buttons["models.languageSetup"].click()
        XCTAssertTrue(app.buttons["setup.close"].waitForExistence(timeout: 5))
        app.buttons["setup.close"].click()
        app.buttons["models.close"].click()
        app.buttons["language.source"].click()
        XCTAssertTrue(app.buttons["language.close"].waitForExistence(timeout: 5))
        let languagePanel = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot())
        languagePanel.name = "language-compact"; languagePanel.lifetime = .keepAlways; add(languagePanel)
        app.buttons["language.legend"].click()
        XCTAssertTrue(app.staticTexts["Speech is available — download the voice"].waitForExistence(timeout: 5))
        let legend = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot())
        legend.name = "language-icon-legend"; legend.lifetime = .keepAlways; add(legend)
        app.buttons["language.close"].click()
        app.buttons["Text"].click()
        let editor = app.textViews.firstMatch
        // Pasting avoids XCTest's intermittent keyboard-event synthesis timeout on macOS.
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        board.clearContents(); board.setString("Kat share test: 23:30", forType: .string)
        let fixtureChange = board.changeCount
        defer { if board.changeCount == fixtureChange { board.clearContents(); board.writeObjects(saved) } }
        editor.click()
        app.menuBars.menuBarItems["Edit"].click()
        app.menuItems["Paste"].click()
        XCTAssertEqual(editor.value as? String, "Kat share test: 23:30")
        app.buttons["text.share.source"].click()
        XCTAssertTrue(app.buttons["Telegram"].waitForExistence(timeout: 5))
        shot("share-installed-telegram")
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    func testPreparedModelSurvivesModeSwitches() {
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-memorySaving", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["Prepare translation"].waitForExistence(timeout: 25))
        app.buttons["Prepare translation"].click()
        let record = app.descendants(matching: .any).matching(identifier: "voice.record").firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 60), "Index must actually finish preparation")
        for _ in 0..<3 {
            app.buttons["Text"].click()
            XCTAssertEqual(app.buttons["text.translate"].label, "Translate")
            app.buttons["Voice"].click()
            XCTAssertTrue(record.exists)
            app.buttons["Image"].click()
            XCTAssertTrue(app.buttons["Open image…"].waitForExistence(timeout: 3))
            app.buttons["Voice"].click()
            XCTAssertTrue(record.waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["Prepare translation"].exists, "Visiting empty Image must preserve the prepared model")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "prepared-after-tab-switches"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate()
    }
    func testInstalledPreparedModelAndHitAreas() {
        let app = XCUIApplication(url: URL(fileURLWithPath: "/Applications/Kat translator.app"))
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-memorySaving", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["Prepare translation"].waitForExistence(timeout: 25))
        app.buttons["Prepare translation"].click()
        // Navigate immediately after Prepare as well as after it finishes.
        XCTAssertTrue(app.buttons["mode.text"].isEnabled)
        app.buttons["mode.text"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2)).click()
        XCTAssertTrue(app.buttons["mode.text"].isSelected)
        app.buttons["mode.voice"].click()
        let record = app.descendants(matching: .any).matching(identifier: "voice.record").firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 60), "Index must actually finish preparation")
        for point in [CGVector(dx: 0.5, dy: 0.5), CGVector(dx: 0.08, dy: 0.2), CGVector(dx: 0.92, dy: 0.8)] {
            app.buttons["mode.text"].coordinate(withNormalizedOffset: point).click()
            XCTAssertEqual(app.buttons["text.translate"].label, "Translate")
            app.buttons["mode.voice"].coordinate(withNormalizedOffset: point).click()
            XCTAssertTrue(record.exists)
            app.buttons["mode.camera"].coordinate(withNormalizedOffset: point).click()
            XCTAssertTrue(app.buttons["Open image…"].waitForExistence(timeout: 3))
            app.buttons["mode.voice"].coordinate(withNormalizedOffset: point).click()
            XCTAssertTrue(record.waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["Prepare translation"].exists, "Visiting empty Image must preserve the prepared model")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "installed-prepared-and-edge-clicks"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate()
    }

    func testModeButtonsRespondAcrossEntireArea() {
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["mode.voice"].waitForExistence(timeout: 25))
        // Each point is deliberately outside the centered text, within the visible pill.
        for point in [CGVector(dx: 0.08, dy: 0.2), CGVector(dx: 0.92, dy: 0.8), CGVector(dx: 0.5, dy: 0.9)] {
            for mode in ["text", "camera", "voice"] {
                let button = app.buttons["mode." + mode]
                button.coordinate(withNormalizedOffset: point).click()
                let selected = NSPredicate(format: "isSelected == true")
                expectation(for: selected, evaluatedWith: button)
                waitForExpectations(timeout: 2)
            }
        }
        app.terminate()
    }

    func testResponsivePanelsAndNativeClose() {
        let app = XCUIApplication()
        app.launchArguments = ["-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 25))
        let initialRight = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0))
        initialRight.click(forDuration: 0.2, thenDragTo: initialRight.withOffset(CGVector(dx: 1180 - window.frame.width, dy: 0)))
        let initialBottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 3))
        initialBottom.click(forDuration: 0.2, thenDragTo: initialBottom.withOffset(CGVector(dx: 0, dy: 900 - window.frame.height)))
        func shot(_ name: String) {
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        app.buttons["Models"].firstMatch.click()
        let close = app.buttons["models.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let wide = app.sheets.firstMatch.frame
        XCTAssertLessThan(close.frame.minY - wide.minY, 65, "Close must share the top header, not create a footer")
        XCTAssertGreaterThan(wide.width, 700)
        XCTAssertLessThanOrEqual(wide.width, window.frame.width)
        XCTAssertLessThan(app.buttons["models.languageSetup"].frame.minY - wide.minY, 110, "No extra header row")
        shot("models-responsive-wide")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model.info.")).firstMatch.click()
        XCTAssertTrue(app.buttons["model.info.close"].waitForExistence(timeout: 5))
        shot("model-details-native-header")
        app.buttons["model.info.close"].click()
        app.buttons["models.languageSetup"].click()
        XCTAssertTrue(app.buttons["setup.close"].waitForExistence(timeout: 5))
        app.buttons["setup.close"].click()
        close.click()
        let right = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0))
        right.click(forDuration: 0.2, thenDragTo: right.withOffset(CGVector(dx: 820 - window.frame.width, dy: 0)))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 3))
        bottom.click(forDuration: 0.2, thenDragTo: bottom.withOffset(CGVector(dx: 0, dy: 740 - window.frame.height)))
        app.buttons["Models"].firstMatch.click()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let narrow = app.sheets.firstMatch.frame
        XCTAssertLessThan(narrow.width, wide.width)
        XCTAssertLessThanOrEqual(narrow.width, window.frame.width)
        XCTAssertLessThan(narrow.height, window.frame.height)
        shot("models-responsive-small")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(close.exists)
        app.buttons["Settings"].firstMatch.click()
        XCTAssertTrue(app.buttons["settings.close"].waitForExistence(timeout: 5))
        shot("settings-native-header")
        app.buttons["Voices and samples"].click()
        XCTAssertTrue(app.buttons["settings.close"].exists)
        shot("nested-voices-native-header")
        app.buttons["settings.close"].click()
        app.buttons["Translation history"].firstMatch.click()
        XCTAssertTrue(app.buttons["history.close"].waitForExistence(timeout: 5))
        shot("history-preview-native-header")
        let expand = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.expand.")).firstMatch
        if expand.exists {
            XCTAssertEqual(expand.value as? String, "collapsed")
            expand.click()
            XCTAssertEqual(expand.value as? String, "expanded")
            shot("history-expanded")
            expand.click()
            XCTAssertEqual(expand.value as? String, "collapsed")
        }
        XCTAssertFalse(app.buttons["Share translation"].exists, "History sharing must not substitute text for audio")
        app.buttons["history.close"].click()
        app.terminate()
    }

}
