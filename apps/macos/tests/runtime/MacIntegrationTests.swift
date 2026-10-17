import XCTest
import AppKit
import Carbon
import OfflineCore
import SwiftUI
@testable import Kat_translator

@MainActor final class MacIntegrationTests: XCTestCase {
    func testSelectionClipboardFallbackRestoresRichDataButPreservesNewerCopies() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("Existing clipboard", forType: .string)
        let rich = NSAttributedString(string: "Existing clipboard", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
        let richData = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        item.setData(richData, forType: .rtf)
        board.writeObjects([item])
        let original = try XCTUnwrap(MacClipboardSnapshot.capture(board))
        board.clearContents(); board.setString("Selection", forType: .string)
        original.restore(board, ifUnchangedSince: board.changeCount)
        XCTAssertEqual(board.string(forType: .string), "Existing clipboard")
        XCTAssertEqual(board.data(forType: .rtf), richData)
        let version = board.changeCount
        board.clearContents(); board.setString("User's newer copy", forType: .string)
        original.restore(board, ifUnchangedSince: version)
        XCTAssertEqual(board.string(forType: .string), "User's newer copy")
        board.clearContents()
        let empty = try XCTUnwrap(MacClipboardSnapshot.capture(board))
        board.setString("Selection", forType: .string)
        empty.restore(board, ifUnchangedSince: board.changeCount)
        XCTAssertNil(board.string(forType: .string))
    }
    func testQuickLanguageFollowsOnboardingUnlessOverridden() throws {
        let name = "quick-language-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(try JSONEncoder().encode(LanguageSetup(primaryID: "ru", targetIDs: ["en"])), forKey: "languageSetup")
        defaults.set("en", forKey: "translationTarget")
        defaults.set("de", forKey: "translationSource")
        XCTAssertEqual(QuickTranslationLanguage.target(defaults: defaults), .russian)
        defaults.set("de", forKey: QuickTranslationLanguage.preferenceKey)
        XCTAssertEqual(QuickTranslationLanguage.target(defaults: defaults), SpeechLanguage(rawValue: "de"))
        XCTAssertEqual(defaults.string(forKey: "translationTarget"), "en")
        defaults.set(try JSONEncoder().encode(LanguageSetup(primaryID: "fr", targetIDs: ["en"])), forKey: "languageSetup")
        XCTAssertEqual(QuickTranslationLanguage.target(defaults: defaults), SpeechLanguage(rawValue: "de"))
        defaults.set("", forKey: QuickTranslationLanguage.preferenceKey)
        XCTAssertEqual(QuickTranslationLanguage.target(defaults: defaults), SpeechLanguage(rawValue: "fr"))
    }
    func testPermissionRefreshRemovesOnlyGrantedPermissionNotice() {
        let model = AppModel(session: ConversationPipeline(asr: IntegrationASR(), translator: IntegrationMT(), speech: IntegrationSpeech(), player: IntegrationPlayer()))
        let integration = model.integration
        defer { integration.cancel() }
        for permission: MacIntegration.Permission in [.selection, .screen] {
            integration.showPermissionWarning(permission)
            XCTAssertNotNil(integration.message)
            integration.applyPermissionStatus(accessibility: permission == .screen, screenCapture: permission == .selection)
            XCTAssertNotNil(integration.message, "Granting a different permission must not hide the notice")
            integration.applyPermissionStatus(accessibility: true, screenCapture: true)
            XCTAssertNil(integration.message)
            XCTAssertFalse(integration.needsAccessibility); XCTAssertFalse(integration.needsScreenCapture)
        }
        integration.message = "Independent translation error"
        integration.applyPermissionStatus(accessibility: true, screenCapture: true)
        XCTAssertEqual(integration.message, "Independent translation error")
    }
    func testShortcutPersistenceDisablingAndConflicts() throws {
        let name = "shortcut-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = MacShortcutSettings(defaults: defaults)
        XCTAssertEqual(settings.shortcut(for: .submit)?.keyCode, 36)
        let chosen = MacShortcut(keyCode: 40, modifiers: [.control, .shift], character: "k")
        XCTAssertNil(settings.set(chosen, for: .submit))
        XCTAssertEqual(MacShortcutSettings(defaults: defaults).shortcut(for: .submit), chosen)
        XCTAssertNotNil(settings.set(chosen, for: .selectedText))
        XCTAssertNil(settings.set(nil, for: .submit))
        XCTAssertNil(MacShortcutSettings(defaults: defaults).shortcut(for: .submit))
        XCTAssertNil(settings.set(chosen, for: .selectedText))
        XCTAssertNotNil(settings.set(MacShortcut(keyCode: 12, modifiers: .command, character: "q"), for: .screenRegion))
        XCTAssertNotNil(settings.set(MacShortcut(keyCode: 0, modifiers: [], character: "a"), for: .selectedText))
        settings.reset()
        XCTAssertEqual(settings.shortcut(for: .submit)?.keyCode, 36)
        XCTAssertEqual(settings.shortcut(for: .selectedText), MacShortcutAction.selectedText.defaultShortcut)
    }
    func testOptionDigitDefaultsDoNotLimitCustomModifierCount() throws {
        let name = "shortcut-count-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = MacShortcutSettings(defaults: defaults)
        let actions: [MacShortcutAction] = [.selectedText, .screenRegion, .clipboardText]
        XCTAssertEqual(MacShortcutAction.allCases.filter(\.global), actions)
        for (index, action) in actions.enumerated() {
            XCTAssertEqual(action.defaultShortcut.modifiers, .option)
            XCTAssertEqual(settings.shortcut(for: action)?.label, "⌥" + String(index + 1))
            // Enabled OS assignments are user-specific and may conflict with any default.
        }
        for modifiers: NSEvent.ModifierFlags in [[.control, .option, .command], [.control, .option, .command, .shift]] {
            let shortcut = MacShortcut(keyCode: 40, modifiers: modifiers, character: "k")
            XCTAssertNil(settings.set(shortcut, for: .selectedText))
            XCTAssertEqual(MacShortcutSettings(defaults: defaults).shortcut(for: .selectedText), shortcut)
        }
    }
    func testNativeEditingCommandsCannotBecomeSubmitShortcuts() throws {
        let settings = MacShortcutSettings(defaults: UserDefaults(suiteName: "kat-reserved-" + UUID().uuidString)!)
        for (code, modifiers, character): (UInt16, NSEvent.ModifierFlags, String) in [
            (6, [.command, .shift], "z"), (123, .option, "x"), (123, [.command, .shift], "x"),
            (51, .option, "x"), (0, .control, "a"), (9, [.command, .option, .shift], "v")
        ] { XCTAssertNotNil(settings.validationError(MacShortcut(keyCode: code, modifiers: modifiers, character: character), for: .submit)) }
        XCTAssertNil(settings.validationError(MacShortcut(keyCode: 40, modifiers: [.control, .option, .shift, .command], character: "k"), for: .submit))
    }
    func testTemporaryAudioCleanupPreservesPersistentHistoryAndOtherFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["KatTextSpeech", "KatSpeechReplay", "KatTextShare", "KatShare", "HistoryExports", "History", "Unrelated"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1, 2]).write(to: directory.appendingPathComponent("audio.m4a"))
        }
        TemporarySpeechFiles.removeExports(in: root)
        for name in ["KatTextSpeech", "KatSpeechReplay", "KatTextShare", "KatShare", "HistoryExports"] { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)) }
        for name in ["History", "Unrelated"] { XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).appendingPathComponent("audio.m4a").path)) }
    }
    func testSharePayloadContainsTextAndAudioTogether() {
        let url = URL(fileURLWithPath: "/fixture.m4a")
        let items = MacSharePresenter.items(text: "Translated text", file: url)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first as? String, "Translated text")
        XCTAssertEqual(items.last as? URL, url)
        XCTAssertEqual(MacSharePresenter.items(text: "Text only", file: nil).count, 1)
    }
    func testCaptureRectangleUsesLocalCoordinatesAndClipsToDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
        XCTAssertEqual(ScreenRegionCapture.clampedRect(from: CGPoint(x: 500, y: 300), to: CGPoint(x: 100, y: 20), bounds: bounds), CGRect(x: 100, y: 20, width: 400, height: 280))
        XCTAssertEqual(ScreenRegionCapture.clampedRect(from: CGPoint(x: 500, y: 300), to: CGPoint(x: 1200, y: 800), bounds: bounds), CGRect(x: 500, y: 300, width: 500, height: 400))
    }
    func testRegistrationConflictSuspensionAndRelease() throws {
        let name = "shortcut-registration-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = MacShortcutSettings(defaults: defaults)
        for action in MacShortcutAction.allCases { settings.set(nil, for: action) }
        let key = MacShortcut(keyCode: 40, modifiers: [.control, .option, .shift, .command], character: "k")
        XCTAssertNil(settings.set(key, for: .selectedText))
        var occupied: EventHotKeyRef?
        XCTAssertEqual(RegisterEventHotKey(UInt32(key.keyCode), key.carbonModifiers, EventHotKeyID(signature: 0x54455354, id: 99), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &occupied), noErr)
        let hotkeys = MacGlobalHotkeys(settings: settings)
        defer { hotkeys.stop(); if let occupied { UnregisterEventHotKey(occupied) } }
        hotkeys.start(); hotkeys.reload()
        XCTAssertNotNil(settings.registrationErrors[.selectedText])
        if let occupied { UnregisterEventHotKey(occupied) }; occupied = nil
        hotkeys.reload(); XCTAssertTrue(settings.registrationErrors.isEmpty)
        settings.recordingAction = .selectedText; hotkeys.reload()
        XCTAssertEqual(RegisterEventHotKey(UInt32(key.keyCode), key.carbonModifiers, EventHotKeyID(signature: 0x54455354, id: 99), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &occupied), noErr)
        hotkeys.stop(); hotkeys.reload() // A queued Combine reload must not register after stop.
        XCTAssertTrue(settings.registrationErrors.isEmpty)
    }
    func testExternalTextPreservesManualSourceAndSameLanguageTarget() async throws {
        let pipeline = ConversationPipeline(asr: IntegrationASR(), translator: IntegrationMT(), speech: IntegrationSpeech(), player: IntegrationPlayer())
        let model = AppModel(session: pipeline)
        let oldLanguages = model.languages
        let defaults = UserDefaults.standard, oldQuick = UserDefaults.standard.object(forKey: QuickTranslationLanguage.preferenceKey)
        defer {
            model.languages = oldLanguages; model.integration.cancel()
            if let oldQuick { defaults.set(oldQuick, forKey: QuickTranslationLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: QuickTranslationLanguage.preferenceKey) }
        }
        defaults.set("ru", forKey: QuickTranslationLanguage.preferenceKey)
        await model.packages.restore()
        await pipeline.prepare(PipelineFiles(asr: nil, translation: FileManager.default.temporaryDirectory, voices: [:], translationModel: .index9B), memorySaving: false)
        model.languages = LanguageSelection(sourceID: "en", targetID: "fr", automaticRequested: false)
        model.integration.accept("12345") // Auto cannot reliably identify this input.
        model.integration.activateRequestedText()
        for _ in 0..<200 where model.integration.working { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.integration.working)
        XCTAssertNil(pipeline.textFields.error)
        XCTAssertFalse(model.languages.automaticRequested)
        XCTAssertEqual(pipeline.textFields.resolvedSource, .english)
        XCTAssertEqual(pipeline.textFields.translatedText, "Translated: 12345")
        model.languages = LanguageSelection(sourceID: "ru", targetID: "en", automaticRequested: false)
        model.integration.accept("12345")
        model.integration.activateRequestedText()
        for _ in 0..<200 where model.integration.working { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(pipeline.textFields.error)
        XCTAssertEqual(pipeline.textFields.resolvedSource, .russian)
        XCTAssertEqual(pipeline.textFields.translatedText, "12345")
        await pipeline.unload()
    }
    func testExternalTextWaitsForRecognitionPreparationAndReleasesIt() async throws {
        let asr = SuspendedIntegrationASR()
        let pipeline = ConversationPipeline(asr: asr, translator: SlowIntegrationMT(), speech: IntegrationSpeech(), player: IntegrationPlayer())
        let model = AppModel(session: pipeline)
        let oldLanguages = model.languages
        let defaults = UserDefaults.standard, oldQuick = UserDefaults.standard.object(forKey: QuickTranslationLanguage.preferenceKey)
        defer {
            model.languages = oldLanguages; model.integration.cancel()
            if let oldQuick { defaults.set(oldQuick, forKey: QuickTranslationLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: QuickTranslationLanguage.preferenceKey) }
        }
        defaults.set("ru", forKey: QuickTranslationLanguage.preferenceKey)
        model.languages = LanguageSelection(sourceID: "en", targetID: "ru", automaticRequested: false)
        await model.packages.restore()
        let url = FileManager.default.temporaryDirectory
        await pipeline.prepare(PipelineFiles(asr: url, translation: url, voices: [:], translationModel: .index9B), memorySaving: false, resultMode: .text)
        let warm = Task { await pipeline.setRecognitionNeeded(true, source: .english) }
        for _ in 0..<200 where !(await asr.loading) { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(pipeline.isPreparingRecognition)
        model.integration.accept("The library opens at nine.")
        XCTAssertTrue(model.integration.working)
        XCTAssertEqual(model.inputMode, .text)
        model.integration.activateRequestedText()
        await Task.yield()
        XCTAssertTrue(pipeline.textFields.sourceText.isEmpty)
        await asr.resolveLoad(); await warm.value
        for _ in 0..<300 where pipeline.textFields.sourceText.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(pipeline.textFields.sourceText, "The library opens at nine.")
        let unloaded = await asr.unloaded
        XCTAssertTrue(unloaded); XCTAssertFalse(pipeline.isRecognitionReady)
        XCTAssertTrue(model.integration.unavailable, "Active translation must still reject another request")
        model.cancel()
        for _ in 0..<300 where model.integration.working { try await Task.sleep(for: .milliseconds(5)) }
        await pipeline.unload()
    }
    func testServicesRoutesToMainTextAndRejectsBusyRequests() async throws {
        let pipeline = ConversationPipeline(asr: IntegrationASR(), translator: IntegrationMT(), speech: IntegrationSpeech(), player: IntegrationPlayer())
        let model = AppModel(session: pipeline)
        let oldLanguages = model.languages
        defer { model.languages = oldLanguages; model.integration.cancel() }
        model.languages = LanguageSelection(sourceID: "en", targetID: "ru", automaticRequested: true)
        await model.packages.restore()
        await pipeline.prepare(PipelineFiles(asr: nil, translation: FileManager.default.temporaryDirectory, voices: [:], translationModel: .index9B), memorySaving: false)
        let integration = model.integration
        var mainOpened = 0
        integration.showMain = { mainOpened += 1 }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let generalChangeCount = NSPasteboard.general.changeCount
        var error: NSString?
        integration.translateSelection(board, userData: nil, error: &error)
        XCTAssertNotNil(error); XCTAssertEqual(integration.text, "")
        board.setString("The library opens at nine.", forType: .string); error = nil
        integration.translateSelection(board, userData: nil, error: &error)
        XCTAssertNil(error); XCTAssertTrue(integration.working); XCTAssertEqual(mainOpened, 1)
        XCTAssertEqual(integration.textRequestID, 1)
        integration.accept("Must not replace the pending source")
        XCTAssertEqual(integration.text, "The library opens at nine.")
        XCTAssertEqual(integration.textRequestID, 1)
        XCTAssertTrue(model.languages.automaticActive(in: .text))
        XCTAssertEqual(model.languages.runtimeTarget, QuickTranslationLanguage.target())
        // The main view starts the request after selecting its Text tab.
        integration.activateRequestedText()
        for _ in 0..<200 where integration.working { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(integration.working)
        XCTAssertEqual(pipeline.textFields.sourceText, integration.text)
        XCTAssertFalse(pipeline.textFields.translatedText.isEmpty)
        XCTAssertTrue(pipeline.quickFields.translatedText.isEmpty)
        XCTAssertEqual(pipeline.activeMode, .text)
        XCTAssertFalse(model.externalOperation)
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCount)
        integration.accept("Cancel before the main window appears")
        model.cancel(); integration.activateRequestedText()
        XCTAssertFalse(integration.working); XCTAssertFalse(model.externalOperation)
        XCTAssertTrue(pipeline.textFields.translatedText.isEmpty)
        await pipeline.unload()
    }
    func testMainTextRequestLeavesImageAndCancellationReleasesControls() async throws {
        let pipeline = ConversationPipeline(asr: IntegrationASR(), translator: SlowIntegrationMT(), speech: IntegrationSpeech(), player: IntegrationPlayer())
        let model = AppModel(session: pipeline)
        let oldLanguages = model.languages
        defer { model.languages = oldLanguages; model.integration.cancel() }
        // Fix both sides of the pair; saved equal languages bypass translation entirely.
        model.languages = LanguageSelection(sourceID: "en", targetID: "ru", automaticRequested: false)
        let defaults = UserDefaults.standard
        let oldQuick = defaults.object(forKey: QuickTranslationLanguage.preferenceKey)
        defaults.set("ru", forKey: QuickTranslationLanguage.preferenceKey)
        defer {
            if let oldQuick { defaults.set(oldQuick, forKey: QuickTranslationLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: QuickTranslationLanguage.preferenceKey) }
        }
        await model.packages.restore()
        model.camera = CameraModel(packages: model.packages, backend: IntegrationMT())
        await model.openCamera()
        await pipeline.prepare(PipelineFiles(asr: nil, translation: FileManager.default.temporaryDirectory, voices: [:], translationModel: .index9B), memorySaving: false)
        model.integration.accept("The library is open.")
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1000, height: 820), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ConversationView(model: model))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<300 where model.usingCamera || !pipeline.isBusy || pipeline.activeMode != .text { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.usingCamera)
        XCTAssertTrue(model.integration.working)
        model.cancel()
        for _ in 0..<300 where model.integration.working { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.integration.working); XCTAssertFalse(model.externalOperation)
        XCTAssertFalse(model.usingCamera, "The shortcut now leaves Image and stays in Text")
        XCTAssertEqual(pipeline.activeMode, .text)
        await pipeline.unload()
    }
    func testScreenImageHandoffOpensImageBeforeOCRAndPreservesText() async throws {
        let model = AppModel(session: ConversationPipeline(asr: IntegrationASR(), translator: IntegrationMT(), speech: IntegrationSpeech(), player: IntegrationPlayer()))
        await model.packages.restore()
        let oldSource = UserDefaults.standard.object(forKey: "translationSource")
        let oldTarget = UserDefaults.standard.object(forKey: "translationTarget")
        let oldAuto = UserDefaults.standard.object(forKey: "automaticLanguage")
        defer {
            for (key, value) in [("translationSource", oldSource), ("translationTarget", oldTarget), ("automaticLanguage", oldAuto)] {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let defaults = UserDefaults.standard
        let oldQuick = defaults.object(forKey: QuickTranslationLanguage.preferenceKey)
        defaults.set("ru", forKey: QuickTranslationLanguage.preferenceKey)
        defer { if let oldQuick { defaults.set(oldQuick, forKey: QuickTranslationLanguage.preferenceKey) } else { defaults.removeObject(forKey: QuickTranslationLanguage.preferenceKey) } }
        model.languages = LanguageSelection(sourceID: "en", targetID: "en", automaticRequested: true)
        model.camera = CameraModel(packages: model.packages, backend: IntegrationMT())
        let picture = NSImage(size: NSSize(width: 900, height: 250), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("The library opens at nine." as NSString).draw(at: NSPoint(x: 30, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
            return true
        }
        let data = try XCTUnwrap(picture.tiffRepresentation)
        // Capture may finish before the main window is recreated.
        model.requestScreenImage(data)
        XCTAssertTrue(model.importingScreenImage)
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1000, height: 820), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ConversationView(model: model))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<2400 where !model.camera.translation.complete { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(model.usingCamera)
        XCTAssertTrue(model.camera.translation.complete, model.camera.error ?? "Image activation interrupted OCR")
        XCTAssertFalse(model.externalOperation)
        XCTAssertFalse(model.importingScreenImage)
        XCTAssertTrue(model.camera.translation.translated.map(\.original).joined().contains("library"))
        XCTAssertEqual(model.camera.source, .english)
        XCTAssertEqual(model.camera.target, .english)
        XCTAssertTrue(model.camera.automaticSource)
        XCTAssertTrue(model.languages.automaticRequested)
        XCTAssertEqual(model.languages.targetID, "en")
        XCTAssertEqual(defaults.string(forKey: "translationTarget"), "en")
        defaults.set("de", forKey: QuickTranslationLanguage.preferenceKey)
        model.languages = LanguageSelection(sourceID: "en", targetID: "fr", automaticRequested: false)
        // A second capture while Image is already selected must still import.
        model.requestScreenImage(data)
        for _ in 0..<2400 where model.importingScreenImage || model.camera.recognizing || model.camera.translation.working { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(model.screenImageRequestID, 2)
        XCTAssertTrue(model.camera.translation.complete)
        XCTAssertEqual(model.camera.target, SpeechLanguage(rawValue: "fr"))
        XCTAssertFalse(model.camera.automaticSource)
        XCTAssertEqual(model.camera.source, .english)
        XCTAssertEqual(model.languages.targetID, "fr")
        XCTAssertEqual(defaults.string(forKey: "translationTarget"), "fr")
        XCTAssertEqual(AppModel(session: ConversationPipeline(asr: IntegrationASR(), translator: IntegrationMT(), speech: IntegrationSpeech(), player: IntegrationPlayer())).languages.targetID, "fr")
        XCTAssertFalse(model.externalOperation)
        // A recreated main view must not reapply an old screenshot over a new text request.
        model.integration.accept("The museum is open today.")
        window.contentView = NSHostingView(rootView: ConversationView(model: model))
        for _ in 0..<200 where model.integration.working { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.integration.working, "An old screenshot must not strand a new text request on Image")
        XCTAssertFalse(model.usingCamera)
        XCTAssertEqual(model.session.textFields.sourceText, "The museum is open today.")
        model.cancel()
        await model.closeCamera()
    }
    func testRegionCancellationCompletesOnlyOnceAndRestoresWindows() {
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 300, height: 200), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        var completions = 0
        let capture = ScreenRegionCapture()
        capture.begin { result in
            completions += 1
            if case .success(nil) = result {} else { XCTFail("Cancel must produce no image") }
        }
        capture.cancel(); capture.cancel()
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(window.isVisible)
    }
    func testShortcutMatchingIgnoresCapsLockButPreservesModifiers() throws {
        let key = MacShortcut(keyCode: 36, modifiers: [], character: "\r")
        func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code))
        }
        XCTAssertTrue(key.matches(try event(36, .capsLock)))
        XCTAssertTrue(key.matches(try event(76, .numericPad)))
        XCTAssertFalse(key.matches(try event(36, .shift)))
    }
}

private actor IntegrationASR: ASRBackend {
    func load(modelURL: URL) async throws {}
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult { ASRResult(text: "Original", language: .english, processingSeconds: 0) }
    nonisolated func cancel() {}
    func unload() async {}
}
private actor SuspendedIntegrationASR: ASRBackend {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var loading = false
    private(set) var unloaded = false
    func load(modelURL: URL) async throws {
        loading = true
        await withCheckedContinuation { continuation = $0 }
    }
    func resolveLoad() { continuation?.resume(); continuation = nil }
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult { ASRResult(text: "Original", language: .english, processingSeconds: 0) }
    nonisolated func cancel() {}
    func unload() async { unloaded = true }
}
private actor IntegrationMT: TranslationBackend {
    func load(modelURL: URL) async throws {}
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        TranslationResult(text: "Translated: " + text, firstTokenSeconds: 0, processingSeconds: 0, fragments: 1)
    }
    nonisolated func cancel() {}
    func unload() async {}
}
private actor IntegrationSpeech: SpeechSynthesisBackend {
    func load(directory: URL, language: SpeechLanguage) async throws {}
    func synthesize(text: String) async throws -> SpeechPCM { SpeechPCM(samples: [0], sampleRate: 22050) }
    nonisolated func cancel() {}
    func unload() async {}
}
@MainActor private final class IntegrationPlayer: SpeechPlayback {
    func play(_ pcm: SpeechPCM) async throws {}
    func play(file: URL) async throws {}
    func stop() {}
    func pause() {}
    func resume() {}
    func setRate(_ rate: Float) {}
}

private actor SlowIntegrationMT: TranslationBackend {
    func load(modelURL: URL) async throws {}
    func translate(text: String, source: SpeechLanguage, target: SpeechLanguage) async throws -> TranslationResult {
        try await Task.sleep(for: .seconds(3))
        return TranslationResult(text: "Slow translation", firstTokenSeconds: 0, processingSeconds: 3, fragments: 1)
    }
    nonisolated func cancel() {}
    func unload() async {}
}
