import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import OfflineCore

@MainActor enum DownloadNotifications {
    private static var permissionRequest: Task<Void, Never>?
    static func started(_ id: String) {
        UserDefaults.standard.set(true, forKey: "downloadNotice." + id)
        guard permissionRequest == nil, AppPlatform.isActive else { return }
        permissionRequest = Task {
            defer { permissionRequest = nil }
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            let readyItems = UserDefaults.standard.dictionary(forKey: "downloadReadyNotices") as? [String: String] ?? [:]
            for (id, title) in readyItems { await ready(id, title: title) }
        }
    }
    static func ready(_ id: String, title: String) async {
        let key = "downloadNotice." + id
        guard UserDefaults.standard.bool(forKey: key) else { return }
        var readyItems = UserDefaults.standard.dictionary(forKey: "downloadReadyNotices") as? [String: String] ?? [:]
        readyItems[id] = title
        UserDefaults.standard.set(readyItems, forKey: "downloadReadyNotices")
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status != .notDetermined else { return }
        // Another completion can arrive while notificationSettings is suspended.
        guard UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        readyItems = UserDefaults.standard.dictionary(forKey: "downloadReadyNotices") as? [String: String] ?? [:]
        readyItems.removeValue(forKey: id)
        UserDefaults.standard.set(readyItems, forKey: "downloadReadyNotices")
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.text("Модель готова")
        content.body = title + L10n.text(" — скачано и проверено. Можно пользоваться офлайн.")
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "model.ready." + id, content: content, trigger: nil))
    }
}

/// Allow verification/assembly to finish after the last background transfer event.
@MainActor final class DownloadBackgroundWork {
    #if os(iOS)
    private var token = UIBackgroundTaskIdentifier.invalid
    init() {
        token = UIApplication.shared.beginBackgroundTask(withName: "Verify downloaded models") { [weak self] in self?.end() }
    }
    func end() {
        if token != .invalid { UIApplication.shared.endBackgroundTask(token); token = .invalid }
    }
    #else
    init() {}
    func end() {}
    #endif
}
