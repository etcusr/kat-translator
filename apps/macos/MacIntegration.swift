import AppKit
import ApplicationServices
import Carbon
import SwiftUI
import OfflineCore

enum QuickTranslationLanguage {
    static let preferenceKey = "quickTranslationTarget"
    static func primary(defaults: UserDefaults = .standard) -> SpeechLanguage {
        if let data = defaults.data(forKey: "languageSetup"),
           let setup = try? JSONDecoder().decode(LanguageSetup.self, from: data),
           let language = SpeechLanguage(rawValue: setup.primaryID) { return language }
        return .russian // The onboarding default; never borrow the last manual direction.
    }
    static func target(defaults: UserDefaults = .standard) -> SpeechLanguage {
        defaults.string(forKey: preferenceKey).flatMap(SpeechLanguage.init(rawValue:)) ?? primary(defaults: defaults)
    }
}

@MainActor final class MacIntegration: NSObject, ObservableObject {
    private weak var model: AppModel?
    private let hotkeys = MacGlobalHotkeys()
    private var task: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApp: NSRunningApplication?
    private var capture: ScreenRegionCapture?
    private var permissionTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    @Published private(set) var text = ""
    @Published var message: String?
    @Published private(set) var working = false
    @Published private(set) var textRequestID = 0
    private var pendingText = false
    @Published var needsAccessibility = false
    @Published var needsScreenCapture = false
    private var showingPermissionMessage = false
    var showMain: (() -> Void)?
    var showSettings: (() -> Void)?
    init(model: AppModel) { self.model = model; super.init() }
    func start() {
        guard activationObserver == nil else { return }
        hotkeys.invoke = { [weak self] action in self?.perform(action) }; hotkeys.start()
        NSApp.servicesProvider = self; NSUpdateDynamicServices()
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in self?.lastExternalApp = app }
        }
    }
    func stop() {
        hotkeys.stop(); cancel(); capture?.cancel(); capture = nil
        permissionTask?.cancel(); permissionTask = nil
        selectionTask?.cancel(); selectionTask = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }; activationObserver = nil
        NSApp.servicesProvider = nil
    }
    var unavailable: Bool {
        guard let model else { return true }
        return task != nil || selectionTask != nil || capture != nil || permissionTask != nil || model.isShuttingDown || model.externalOperation || (model.session.isBusy && !model.session.isPreparingRecognition) || model.recorder.isRecording || model.recorder.starting || model.preparingRecording || model.finishing || model.importingAudio || model.changingTranslation || model.camera.opening || model.camera.recognizing || model.camera.translation.working
    }
    func perform(_ action: MacShortcutAction) {
        switch action {
        case .selectedText: selectedText()
        case .clipboardText: clipboardText()
        case .screenRegion: captureRegion()
        default: break
        }
    }
    func selectedText() {
        guard !unavailable else { busyNotice(); return }
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApp : front
        guard AXIsProcessTrusted() else {
            showPermissionWarning(.selection)
            // Ask only after the user invokes selection translation, never at launch.
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            return
        }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { showMessage(L10n.text("Сначала выделите текст в другом приложении.")); return }
        selectionTask = Task {
            let selected = await MacSelectedText.read(from: app)
            selectionTask = nil
            guard !Task.isCancelled else { return }
            if let selected { accept(selected) } else { selectionMissing() }
        }
    }
    private func selectionMissing() {
        showMessage(L10n.text("Выделенный текст недоступен. Скопируйте его и нажмите «Перевести из буфера» или воспользуйтесь меню «Службы»."))
    }
    func clipboardText() {
        guard !unavailable else { busyNotice(); return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { showMessage(L10n.text("В буфере обмена нет текста.")); return }
        accept(text)
    }
    @objc func translateSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = L10n.text("Выделенный текст недоступен.") as NSString; return
        }
        accept(text)
    }
    func accept(_ source: String) {
        guard !unavailable, let model else { busyNotice(); return }
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        model.selectInputMode(.text)
        text = source; message = nil; needsAccessibility = false; needsScreenCapture = false; showingPermissionMessage = false
        let target = QuickTranslationLanguage.target()
        model.languages = LanguageSelection(sourceID: model.languages.sourceID, targetID: target.rawValue, automaticRequested: model.languages.automaticRequested)
        model.message = nil; model.session.clearFields(in: .text)
        pendingText = true; working = true; model.externalOperation = true
        textRequestID += 1
        showMain?()
    }
    /// Start only after the main window has switched to Text, including when reopening it.
    func activateRequestedText() {
        guard pendingText, task == nil, let model, !model.isShuttingDown else { return }
        pendingText = false
        let source = text
        task = Task {
            defer { working = false; model.externalOperation = false; task = nil }
            await model.closeCamera()
            await model.synchronizeRecognition()
            await model.packages.restore()
            guard !Task.isCancelled, !model.isShuttingDown else { return }
            guard model.packages.ready, model.packages.translationTermsAccepted else {
                message = L10n.text("Сначала скачайте модель перевода в разделе «Модели»."); return
            }
            if !model.session.isReady { await model.load(resultMode: .text) }
            guard !Task.isCancelled, !model.isShuttingDown else { return }
            if model.session.isReady { await model.translateText(source) }
            else { message = model.session.textFields.error ?? L10n.text("Не удалось подготовить перевод.") }
        }
    }
    func cancel() {
        if pendingText {
            pendingText = false; working = false; model?.externalOperation = false
        }
        guard task != nil else { return }
        task?.cancel(); model?.session.cancel()
    }
    private func busyNotice() {
        if capture != nil || selectionTask != nil { NSSound.beep(); return }
        showMessage(L10n.text("Сейчас выполняется другая операция. Дождитесь её завершения и повторите."))
    }
    private func showMessage(_ value: String) { showingPermissionMessage = false; message = value; showMain?() }
    enum Permission { case selection, screen }
    func showPermissionWarning(_ permission: Permission) {
        needsAccessibility = permission == .selection
        needsScreenCapture = permission == .screen
        showMessage(permission == .selection
            ? L10n.text("Разрешите «Универсальный доступ», чтобы читать выделенный текст. Можно также скопировать текст и нажать «Перевести из буфера»." )
            : L10n.text("Для перевода области экрана разрешите запись экрана в настройках macOS."))
        showingPermissionMessage = true
    }
    func refreshPermissions() {
        applyPermissionStatus(accessibility: AXIsProcessTrusted(), screenCapture: CGPreflightScreenCaptureAccess())
    }
    /// Preserve unrelated errors and drafts when a permission warning becomes obsolete.
    func applyPermissionStatus(accessibility: Bool, screenCapture: Bool) {
        if accessibility && needsAccessibility { needsAccessibility = false }
        if screenCapture && needsScreenCapture { needsScreenCapture = false }
        if showingPermissionMessage && !needsAccessibility && !needsScreenCapture {
            message = nil; showingPermissionMessage = false
        }
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        HotkeySettingsView.openPrivacy("Privacy_Accessibility")
    }
    func requestScreenCapture() {
        requestScreenCapture(startCapture: false, showSettingsIfDenied: true)
    }
    func captureRegion() {
        guard !unavailable else { busyNotice(); return }
        if CGPreflightScreenCaptureAccess() { beginRegionCapture() }
        else { requestScreenCapture(startCapture: true, showSettingsIfDenied: false) }
    }
    private func requestScreenCapture(startCapture: Bool, showSettingsIfDenied: Bool) {
        guard !unavailable else { busyNotice(); return }
        permissionTask = Task {
            let granted = await ScreenRegionCapture.requestPermission()
            guard !Task.isCancelled else { return }
            permissionTask = nil
            needsScreenCapture = !granted
            if granted {
                message = nil
                if startCapture { beginRegionCapture() }
            } else {
                showPermissionWarning(.screen)
                if showSettingsIfDenied { HotkeySettingsView.openPrivacy("Privacy_ScreenCapture") }
            }
        }
    }
    private func beginRegionCapture() {
        guard !unavailable, let model else { busyNotice(); return }
        message = nil
        let capture = ScreenRegionCapture(); self.capture = capture
        capture.begin { [weak self] result in
            guard let self else { return }
            self.capture = nil
            switch result {
            case .success(nil): break
            case .failure(let error): self.showMessage(error.localizedDescription)
            case .success(let data?):
                guard !self.unavailable else { self.busyNotice(); return }
                self.showMain?()
                model.requestScreenImage(data)
            }
        }
    }
}

/// Some browser pages and custom editors do not expose AXSelectedText. A Copy
/// fallback is bounded to the explicitly invoked app and restores clipboard data.
@MainActor enum MacSelectedText {
    static func read(from app: NSRunningApplication) async -> String? {
        guard !IsSecureEventInputEnabled() else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // A timeout set on one element applies only to it; the system-wide element sets the
        // default for every element, so a hung target app cannot freeze Kat for seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.2)
        AXUIElementSetMessagingTimeout(root, 0.2)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            var element = unsafeBitCast(focused, to: AXUIElement.self)
            let deadline = Date().addingTimeInterval(0.6)
            for _ in 0..<6 {
                var subrole: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
                if subrole as? String == kAXSecureTextFieldSubrole { return nil }
                var selected: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
                   let text = selected as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                var marker: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &marker) == .success,
                   let marker,
                   AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, marker, &selected) == .success,
                   let text = selected as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                guard Date() < deadline else { break }
                var parent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                      let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                element = unsafeBitCast(parent, to: AXUIElement.self)
            }
        }
        guard !Task.isCancelled, !IsSecureEventInputEnabled() else { return nil }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            app.activate(options: [])
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { break }
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return nil }
            }
        }
        // Let the invocation's modifiers come up before sending the Copy command.
        for _ in 0..<20 {
            if CGEventSource.flagsState(.combinedSessionState).intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]).isEmpty { break }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return nil }
        }
        guard !Task.isCancelled, !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let snapshot = MacClipboardSnapshot.capture(.general) else { return nil }
        let board = NSPasteboard.general, before = board.changeCount
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return nil }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        // Do not clear the clipboard first: an unsupported Copy leaves it intact.
        for _ in 0..<30 {
            if board.changeCount != before { break }
            // Once Copy has been sent, cancellation must still wait for its
            // clipboard update so the original data can be restored.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { continuation.resume() }
            }
        }
        let copiedVersion = board.changeCount
        guard copiedVersion != before else { return nil }
        defer { snapshot.restore(board, ifUnchangedSince: copiedVersion) }
        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              board.types?.contains(.fileURL) != true,
              let text = board.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

@MainActor struct MacClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    static func capture(_ board: NSPasteboard) -> Self? {
        var items: [[NSPasteboard.PasteboardType: Data]] = [], size = 0
        for item in board.pasteboardItems ?? [] {
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                size += data.count
                guard size <= 64 * 1024 * 1024 else { return nil }
                values[type] = data
            }
            items.append(values)
        }
        return Self(items: items)
    }
    func restore(_ board: NSPasteboard, ifUnchangedSince version: Int) {
        // Never overwrite a later Copy performed by the user or another app.
        guard board.changeCount == version else { return }
        let restored = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        board.clearContents()
        if !restored.isEmpty { board.writeObjects(restored) }
    }
}
