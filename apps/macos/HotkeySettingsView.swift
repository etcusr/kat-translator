import SwiftUI
import AppKit
import ApplicationServices
import OfflineCore

struct HotkeySettingsView: View {
    @ObservedObject private var settings = MacShortcutSettings.shared
    @ObservedObject private var packages = PackageDownloadCoordinator.shared
    @AppStorage(QuickTranslationLanguage.preferenceKey) private var quickTarget = ""
    @State private var error: String?
    @State private var accessibility = AXIsProcessTrusted()
    @State private var screenCapture = CGPreflightScreenCaptureAccess()
    @State private var requestingScreenCapture = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        Form {
            Section {
                Picker(L10n.text("Язык быстрого перевода"), selection: $quickTarget) {
                    Text(L10n.text("Основной язык: ") + TranslationLanguage.name(QuickTranslationLanguage.primary().rawValue)).tag("")
                    ForEach(TranslationLanguage.supported(by: packages.selectedTranslation).sorted { $0.displayName < $1.displayName }) { language in
                        Text(language.displayName).tag(language.id)
                    }
                    if !quickTarget.isEmpty, !TranslationLanguage.supported(by: packages.selectedTranslation).contains(where: { $0.id == quickTarget }) {
                        Text(TranslationLanguage.name(quickTarget)).tag(quickTarget)
                    }
                }.accessibilityIdentifier("shortcuts.targetLanguage")
                if !TranslationLanguage.details(QuickTranslationLanguage.target()).connected(to: packages.selectedTranslation) {
                    Text(PipelineError.modelLanguageUnavailable.localizedDescription).foregroundStyle(.orange)
                }
                ForEach(MacShortcutAction.allCases.filter(\.global)) { row($0) }
            } header: { SettingsSectionHeader(L10n.text("Из других приложений")) }
            footer: { Text(L10n.text("Для выделенного текста и буфера. По умолчанию используется основной язык, выбранный при первом запуске. Для области экрана используется язык, выбранный в главном окне. Работает, пока Kat translator запущен.")) }
            Section {
                ForEach(MacShortcutAction.allCases.filter { !$0.global }) { row($0) }
            } header: { SettingsSectionHeader(L10n.text("Внутри приложения")) }
            footer: { Text(L10n.text("Стандартные команды редактирования macOS остаются системными. Shift+Enter добавляет новую строку.")) }
            Section {
                permissionRow(L10n.text("Выделенный текст"), granted: accessibility, identifier: "accessibility") {
                    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    Self.openPrivacy("Privacy_Accessibility")
                }
                permissionRow(L10n.text("Снимок области экрана"), granted: screenCapture, identifier: "screen") {
                    guard !requestingScreenCapture else { return }
                    requestingScreenCapture = true
                    Task {
                        screenCapture = await ScreenRegionCapture.requestPermission()
                        requestingScreenCapture = false
                        if !screenCapture { Self.openPrivacy("Privacy_ScreenCapture") }
                    }
                }.disabled(requestingScreenCapture)
            } header: { SettingsSectionHeader(L10n.text("Доступ macOS")) }
            footer: { Text(L10n.text("Выделенный текст читается через «Универсальный доступ», снимок — через «Запись экрана». Служба в контекстном меню и явный перевод из буфера не требуют доступа к другим приложениям.")) }
            Section {
                Text(L10n.text("В приложениях с поддержкой служб: выделите текст → правый клик → Службы → Перевести в Kat translator."))
                Text(L10n.text("Проверяем системные и известные стандартные сочетания браузеров и Telegram. Пользовательские сочетания и расширения других приложений могут потребовать переназначения."))
                Button(L10n.text("Сбросить горячие клавиши")) { settings.reset() }.accessibilityIdentifier("shortcuts.reset")
            }
        }.formStyle(.grouped).katDesktopPanelSurface()
            .navigationTitle(L10n.text("Горячие клавиши"))
            .onReceive(timer) { _ in accessibility = AXIsProcessTrusted(); screenCapture = CGPreflightScreenCaptureAccess() }
            .sheet(item: $settings.recordingAction, onDismiss: { error = nil }) { action in
                VStack(spacing: 20) {
                    Text(action.title).font(.title2)
                    Text(L10n.text("Нажмите новое сочетание клавиш"))
                    ShortcutRecorder { event in
                        if event.keyCode == 53 && event.modifierFlags.intersection(MacShortcut.modifierMask).isEmpty {
                            settings.recordingAction = nil; return
                        }
                        error = settings.set(MacShortcut(event: event), for: action)
                        if error == nil { settings.recordingAction = nil }
                    }.frame(width: 1, height: 1).accessibilityIdentifier("shortcuts.recorder")
                    if let error { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                    Text(L10n.text("Esc — отменить изменение")).font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.text("Отключить")) { settings.set(nil, for: action); settings.recordingAction = nil }
                            .accessibilityIdentifier("shortcuts.disable")
                        Spacer()
                        Button(L10n.text("Отмена")) { settings.recordingAction = nil }
                    }
                }.padding(24).frame(width: 440).background(Color(nsColor: .windowBackgroundColor))
                    .preferredColorScheme(.dark).tint(KatTheme.accent)
            }
            .onDisappear { settings.recordingAction = nil }
    }
    private func row(_ action: MacShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(action.title).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(settings.shortcut(for: action)?.label ?? L10n.text("Отключено")) {
                    error = nil; settings.recordingAction = action
                }.buttonStyle(.bordered).frame(minWidth: 115, alignment: .trailing)
                    .accessibilityIdentifier("shortcuts.record." + action.rawValue)
            }.frame(minHeight: 34)
            if let error = settings.registrationErrors[action] { Text(error).font(.callout).foregroundStyle(.orange) }
        }
    }
    private func permissionRow(_ title: String, granted: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.circle" : "lock")
            Spacer()
            if granted { Text(L10n.text("Разрешено")).foregroundStyle(.secondary) }
            else { Button(L10n.text("Разрешить…"), action: action).accessibilityIdentifier("shortcuts.permission." + identifier) }
        }
    }
    static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    var receive: (NSEvent) -> Void
    func makeNSView(context: Context) -> RecorderView { let view = RecorderView(); view.receive = receive; return view }
    func updateNSView(_ view: RecorderView, context: Context) { view.receive = receive }
    static func dismantleNSView(_ view: RecorderView, coordinator: ()) { view.stop() }
    final class RecorderView: NSView {
        var receive: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window,
                      window.isKeyWindow || window.sheetParent?.isKeyWindow == true,
                      event.window === window || event.window === window.sheetParent else { return event }
                if !event.isARepeat { self.receive?(event) }
                return nil
            }
            DispatchQueue.main.async { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self) }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        override func keyDown(with event: NSEvent) { if !event.isARepeat { receive?(event) } }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            if !event.isARepeat { receive?(event) }; return true
        }
    }
}
