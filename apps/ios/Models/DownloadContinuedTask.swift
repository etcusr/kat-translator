import Foundation
import BackgroundTasks
import OfflineCore

/// One user-initiated batch, including network transfer, verification and unpacking.
/// The system owns the progress UI while it grants continued execution.
@available(iOS 26.0, *)
@MainActor enum DownloadContinuedTask {
    private static var requestID: String?
    private static var task: BGContinuedProcessingTask?
    private static var stopping = false
    static var ownsPresentation: Bool { requestID != nil }

    static func start(onChange: @escaping () -> Void, onExpiration: @escaping () async -> Void) -> Bool {
        if ownsPresentation { return true }
        let id = "app.kattranslator.model-download." + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { delivered in
            Task { @MainActor in
                guard let continued = delivered as? BGContinuedProcessingTask, requestID == id else {
                    delivered.setTaskCompleted(success: false)
                    return
                }
                task = continued
                continued.expirationHandler = {
                    Task { @MainActor in
                        guard requestID == id, !stopping else { return }
                        stopping = true
                        // Expiration also represents the user's Stop action. Preserve
                        // resume data and installed packages, and stop queue monitors.
                        await onExpiration()
                        finish(success: false)
                        onChange()
                    }
                }
                NSLog("KatDownload continued started")
                onChange()
            }
        }
        guard registered else { return false }
        let request = BGContinuedProcessingTaskRequest(identifier: id,
            title: L10n.text("Загрузка моделей"), subtitle: L10n.text("Подготовка…"))
        // Never leave a queued task that could appear after its transfers finish.
        request.strategy = .fail
        requestID = id
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            requestID = nil
            NSLog("KatDownload continued unavailable: %@", String(describing: error))
            return false
        }
    }

    static func publish(_ value: DownloadProgress, title: String, detail: String) {
        guard ownsPresentation, !stopping else { return }
        if let task {
            // Reserve the final unit for verification/assembly; do not report
            // task completion merely because all network bytes have arrived.
            let total = max(1, value.total)
            task.progress.totalUnitCount = total + 1
            task.progress.completedUnitCount = value.status == .ready ? total + 1 : min(value.received, total)
            let percent = Int(value.fraction * 100)
            task.updateTitle(title, subtitle: "\(percent)% · \(detail)")
            NSLog("KatDownload continued bytes=%lld/%lld percent=%d status=%@", value.received, value.total, percent, String(describing: value.status))
        }
        if value.finished || value.status == .paused { finish(success: value.status == .ready) }
    }

    private static func finish(success: Bool) {
        let current = task
        let pending = requestID
        task = nil; requestID = nil; stopping = false
        if let current { current.setTaskCompleted(success: success) }
        else if let pending { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: pending) }
        NSLog("KatDownload continued completed success=%d", success ? 1 : 0)
    }
}
