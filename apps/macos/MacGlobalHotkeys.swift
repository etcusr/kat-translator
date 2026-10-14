import AppKit
import Carbon
import Combine
import OfflineCore

@MainActor final class MacGlobalHotkeys {
    private let settings: MacShortcutSettings
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var pressed = Set<UInt32>()
    private var observation: AnyCancellable?
    var invoke: ((MacShortcutAction) -> Void)?
    init(settings: MacShortcutSettings = .shared) { self.settings = settings }
    func start() {
        guard handler == nil else { return }
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x4B415454 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<MacGlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.pressed.remove(id.id) }
                else if owner.pressed.insert(id.id).inserted,
                        let action = MacShortcutAction.allCases.enumerated().first(where: { UInt32($0.offset + 1) == id.id })?.element { owner.invoke?(action) }
            }
            return noErr
        }, events.count, &events, context, &handler)
        guard status == noErr else {
            settings.registrationErrors = Dictionary(uniqueKeysWithValues: MacShortcutAction.allCases.filter(\.global).map { ($0, L10n.text("Не удалось включить глобальные горячие клавиши.")) }); return
        }
        observation = settings.$revision.combineLatest(settings.$recordingAction).sink { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
    }
    func reload() {
        guard handler != nil else { return }
        for item in registrations { UnregisterEventHotKey(item) }; registrations = []; pressed = []
        settings.registrationErrors = [:]
        guard settings.recordingAction == nil else { return }
        for (index, action) in MacShortcutAction.allCases.enumerated() where action.global {
            guard let key = settings.shortcut(for: action) else { continue }
            if let error = settings.validationError(key, for: action) { settings.registrationErrors[action] = error; continue }
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key.keyCode), key.carbonModifiers, EventHotKeyID(signature: 0x4B415454, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { registrations.append(reference) }
            else { settings.registrationErrors[action] = L10n.text("Сочетание занято другим приложением или недоступно. Выберите другое.") }
        }
    }
    func stop() {
        observation = nil
        for item in registrations { UnregisterEventHotKey(item) }; registrations = []; pressed = []
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
}
