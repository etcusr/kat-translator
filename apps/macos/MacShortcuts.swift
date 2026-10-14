import AppKit
import Carbon
import Combine
import SwiftUI
import OfflineCore

struct MacShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifierBits: UInt
    let character: String
    static let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let functionKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, character: String) {
        self.keyCode = keyCode; modifierBits = modifiers.intersection(Self.modifierMask).rawValue
        self.character = character.lowercased()
    }
    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags, character: event.charactersIgnoringModifiers ?? "")
    }
    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierBits) }
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
    var eventModifiers: SwiftUI.EventModifiers {
        var value: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { value.insert(.command) }
        if modifiers.contains(.option) { value.insert(.option) }
        if modifiers.contains(.control) { value.insert(.control) }
        if modifiers.contains(.shift) { value.insert(.shift) }
        return value
    }
    var keyEquivalent: KeyEquivalent {
        switch keyCode {
        case 36, 76: return .return
        case 53: return .escape
        case 48: return .tab
        case 49: return .space
        case 51: return .delete
        default: return KeyEquivalent(character.first ?? "\0")
        }
    }
    var label: String {
        let prefix = (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "") + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
        let name: String
        switch keyCode {
        case 36, 76: name = "Enter"
        case 53: name = "Esc"
        case 49: name = "Space"
        case 48: name = "Tab"
        case 51: name = "⌫"
        case 123: name = "←"
        case 124: name = "→"
        case 125: name = "↓"
        case 126: name = "↑"
        case 115: name = "Home"
        case 119: name = "End"
        case 116: name = "Page Up"
        case 121: name = "Page Down"
        case 117: name = "⌦"
        default: name = Self.functionKeyCodes.firstIndex(of: keyCode).map { "F" + String($0 + 1) } ?? character.uppercased()
        }
        return prefix + name
    }
    private var canonicalKeyCode: UInt16 { keyCode == 76 ? 36 : keyCode }
    func sameKeys(as other: Self) -> Bool { canonicalKeyCode == other.canonicalKeyCode && modifierBits == other.modifierBits }
    func matches(_ event: NSEvent) -> Bool {
        (event.keyCode == 76 ? 36 : event.keyCode) == canonicalKeyCode && event.modifierFlags.intersection(Self.modifierMask) == modifiers
    }
}

enum MacShortcutAction: String, CaseIterable, Identifiable {
    case submit, selectedText, screenRegion, clipboardText, imageOpen, imagePaste, cancel
    var id: String { rawValue }
    var global: Bool { [.selectedText, .clipboardText, .screenRegion].contains(self) }
    var title: String {
        switch self {
        case .submit: L10n.text("Перевести текст")
        case .selectedText: L10n.text("Перевести выделенный текст")
        case .clipboardText: L10n.text("Перевести текст из буфера")
        case .screenRegion: L10n.text("Перевести область экрана")
        case .imageOpen: L10n.text("Открыть изображение…")
        case .imagePaste: L10n.text("Вставить изображение")
        case .cancel: L10n.text("Отмена / закрыть всплывающее окно")
        }
    }
    var defaultShortcut: MacShortcut {
        switch self {
        case .submit: MacShortcut(keyCode: 36, modifiers: [], character: "\r")
        case .selectedText: MacShortcut(keyCode: 18, modifiers: .option, character: "1")
        case .screenRegion: MacShortcut(keyCode: 19, modifiers: .option, character: "2")
        case .clipboardText: MacShortcut(keyCode: 20, modifiers: .option, character: "3")
        case .imageOpen: MacShortcut(keyCode: 31, modifiers: .command, character: "o")
        case .imagePaste: MacShortcut(keyCode: 9, modifiers: .command, character: "v")
        case .cancel: MacShortcut(keyCode: 53, modifiers: [], character: "\u{1b}")
        }
    }
}

@MainActor final class MacShortcutSettings: ObservableObject {
    static let shared = MacShortcutSettings(defaults: ProcessInfo.processInfo.environment["KAT_SHORTCUTS_TEST_SUITE"].flatMap { UserDefaults(suiteName: $0) } ?? .standard)
    private struct Binding: Codable { var shortcut: MacShortcut? }
    private let defaults: UserDefaults
    @Published private var bindings: [String: Binding]
    @Published private(set) var revision = 0
    @Published var recordingAction: MacShortcutAction?
    @Published var registrationErrors: [MacShortcutAction: String] = [:]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = defaults.data(forKey: "macShortcuts").flatMap { try? JSONDecoder().decode([String: Binding].self, from: $0) } ?? [:]
    }
    func shortcut(for action: MacShortcutAction) -> MacShortcut? {
        if let value = bindings[action.rawValue] { return value.shortcut }
        return action.defaultShortcut
    }
    @discardableResult func set(_ shortcut: MacShortcut?, for action: MacShortcutAction) -> String? {
        if let shortcut {
            if let error = validationError(shortcut, for: action) { return error }
            if let other = MacShortcutAction.allCases.first(where: { $0 != action && self.shortcut(for: $0)?.sameKeys(as: shortcut) == true }) {
                return L10n.text("Это сочетание уже используется: ") + other.title
            }
        }
        bindings[action.rawValue] = Binding(shortcut: shortcut)
        save(); return nil
    }
    func reset() { bindings = [:]; save() }
    private func save() { defaults.set(try? JSONEncoder().encode(bindings), forKey: "macShortcuts"); revision += 1 }
    func validationError(_ shortcut: MacShortcut, for action: MacShortcutAction) -> String? {
        let flags = shortcut.modifiers
        guard shortcut.keyCode < 128, !shortcut.character.isEmpty else { return L10n.text("Выберите другую клавишу.") }
        if [36, 76].contains(shortcut.keyCode) && flags == .shift { return L10n.text("Shift+Enter оставлен для новой строки.") }
        let functionKeys = MacShortcut.functionKeyCodes
        if action.global && flags.intersection([.command, .control, .option]).isEmpty && !functionKeys.contains(shortcut.keyCode) {
            return L10n.text("Добавьте ⌘, ⌃ или ⌥, чтобы не мешать вводу текста.")
        }
        if !action.global && flags.intersection([.command, .control, .option]).isEmpty && ![36, 76, 53].contains(shortcut.keyCode) && !functionKeys.contains(shortcut.keyCode) { return L10n.text("Добавьте ⌘, ⌃ или ⌥, чтобы не мешать вводу текста.") }
        if flags == .command && [0, 6, 7, 8, 9, 12, 13, 4, 46, 43, 48, 49].contains(shortcut.keyCode) && !(action == .imagePaste && shortcut.keyCode == 9) {
            return L10n.text("Это стандартное сочетание macOS для редактирования или управления окнами.")
        }
        if flags == [.command, .shift] && [6, 7, 8].contains(shortcut.keyCode)
            || flags == [.command, .option, .shift] && shortcut.keyCode == 9
            || flags.intersection([.command, .option]).isEmpty == false && [51, 117, 123, 124, 125, 126, 115, 119].contains(shortcut.keyCode)
            || flags == .control && [0, 2, 3, 4, 11, 14, 16, 35, 40, 45, 17, 32, 9].contains(shortcut.keyCode) {
            return L10n.text("Это стандартное сочетание macOS для редактирования или управления окнами.")
        }
        if action.global {
            if Self.systemConflict(shortcut) { return L10n.text("Это сочетание включено в системных настройках macOS.") }
            // Common browser/Telegram bindings are local: Carbon alone cannot detect them.
            if flags == .command && [17, 31, 45, 37, 3, 15, 35, 1, 11, 34, 32, 40, 14, 38, 16, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29].contains(shortcut.keyCode)
                || flags == [.command, .option] && [17, 1, 3, 34, 38, 8, 37, 9, 11, 32, 35, 45].contains(shortcut.keyCode)
                || flags == [.command, .shift] && [17, 1, 3, 4, 12, 31, 35, 45, 46, 9, 11, 40, 7, 8].contains(shortcut.keyCode) {
                return L10n.text("Это сочетание используется в браузерах или Telegram. Выберите другое.")
            }
        }
        return nil
    }
    static func systemConflict(_ shortcut: MacShortcut) -> Bool {
        var values: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&values) == noErr, let rows = values?.takeRetainedValue() as? [[String: Any]] else { return false }
        return rows.contains { row in
            (row[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
            (row[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint16Value == shortcut.keyCode &&
            (row[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == shortcut.carbonModifiers
        }
    }
    var submitHint: String {
        if let key = shortcut(for: .submit) { return key.label + L10n.text(" — перевести · Shift+Enter — новая строка") }
        return L10n.text("Enter — новая строка")
    }
}

private struct MacActionShortcut: ViewModifier {
    @ObservedObject private var settings = MacShortcutSettings.shared
    let action: MacShortcutAction
    var enabled = true
    @ViewBuilder func body(content: Content) -> some View {
        if enabled, let shortcut = settings.shortcut(for: action), settings.recordingAction == nil {
            content.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
        } else { content.keyboardShortcut(nil) }
    }
}
extension View {
    func macShortcut(_ action: MacShortcutAction, enabled: Bool = true) -> some View { modifier(MacActionShortcut(action: action, enabled: enabled)) }
}

struct MacTextSubmitHandler: NSViewRepresentable {
    var focused: Bool
    var busy: Bool
    var submit: () -> Void
    func makeNSView(context: Context) -> Anchor { let view = Anchor(); view.update(self); return view }
    func updateNSView(_ view: Anchor, context: Context) { view.update(self) }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stop() }
    final class Anchor: NSView {
        var config: MacTextSubmitHandler?
        var monitor: Any?
        func update(_ value: MacTextSubmitHandler) { config = value }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let config = self.config, config.focused,
                      event.window === self.window, self.window?.isKeyWindow == true, self.window?.attachedSheet == nil,
                      MacShortcutSettings.shared.recordingAction == nil,
                      MacShortcutSettings.shared.shortcut(for: .submit)?.matches(event) == true,
                      let editor = self.window?.firstResponder as? NSTextView, !editor.hasMarkedText() else { return event }
                if !event.isARepeat && !config.busy { config.submit() }
                return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
