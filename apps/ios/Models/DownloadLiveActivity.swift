import ActivityKit
import UIKit
import OfflineCore

/// Prefer system continued processing for a user-started batch on iOS 26+.
/// The custom ActivityKit presentation remains the fallback when unavailable.
@MainActor enum DownloadLiveActivity {
    private static var activity: Activity<DownloadActivityAttributes>?
    private static var ids = Set(UserDefaults.standard.stringArray(forKey: "liveDownloadIDs") ?? [])
    private static var scheduled: Task<Void, Never>?
    private static var revision = 0
    private static var publishedRevision = 0
    private static var lastUpdate = Date.distantPast
    private static var systemPresentation: Bool {
        if #available(iOS 26.0, *) { return DownloadContinuedTask.ownsPresentation }
        return false
    }
    static func started(_ id: String) {
        if activity == nil { activity = Activity<DownloadActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale } }
        if activity == nil && !systemPresentation { ids.removeAll() }
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: "liveDownloadIDs")
        if #available(iOS 26.0, *), UIApplication.shared.applicationState == .active, !systemPresentation {
            if DownloadContinuedTask.start(onChange: { changed() }, onExpiration: { await PackageDownloadCoordinator.shared.pauseAll() }), let previous = activity {
                activity = nil
                Task { await previous.end(nil, dismissalPolicy: .immediate) }
            }
        }
        if activity == nil, !systemPresentation, UIApplication.shared.applicationState == .active, ActivityAuthorizationInfo().areActivitiesEnabled {
            let content = snapshot()
            activity = try? Activity.request(attributes: DownloadActivityAttributes(staleMessage: L10n.text("Прогресс обновится, когда iOS передаст новые данные."), catCoat: Int.random(in: 0..<CatCoat.allCases.count)), content: ActivityContent(state: content, staleDate: Date().addingTimeInterval(60)), pushType: nil)
        }
        changed()
    }
    static func changed() {
        revision += 1
        guard scheduled == nil else { return }
        scheduled = Task {
            // Limit UI updates without pretending that suspended code can run a timer.
            let delay = max(0, 2 - Date().timeIntervalSince(lastUpdate))
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            let observedRevision = revision
            defer {
                publishedRevision = observedRevision
                scheduled = nil
                if revision != observedRevision { changed() }
            }
            if #available(iOS 26.0, *), systemPresentation {
                let progress = aggregateProgress()
                let state = snapshot(progress)
                lastUpdate = Date()
                DownloadContinuedTask.publish(progress, title: state.title, detail: state.bytes)
                return
            }
            if activity == nil { activity = Activity<DownloadActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale } }
            guard let current = activity, !ids.isEmpty else { return }
            let state = snapshot()
            lastUpdate = Date()
            let content = ActivityContent(state: state, staleDate: state.finished ? nil : Date().addingTimeInterval(60))
            if state.finished {
                activity = nil
                await current.end(content, dismissalPolicy: .after(Date().addingTimeInterval(300)))
            } else { await current.update(content) }
        }
    }
    /// Drain through this caller's revision, including a newer snapshot queued
    /// behind an ActivityKit update already in flight. Call before returning a
    /// background URLSession completion handler, while iOS still grants runtime.
    static func flush() async {
        changed()
        let target = revision
        while publishedRevision < target, let pending = scheduled {
            await pending.value
        }
    }
    static func refreshAfterLifecycleChange() {
        guard !ids.isEmpty else { return }
        // A short, expiring allowance only to publish the current snapshot.
        // It does not keep the app alive for the duration of the download.
        let background = DownloadBackgroundWork()
        Task {
            defer { background.end() }
            await flush()
        }
    }
    private static func aggregateProgress() -> DownloadProgress {
        let coordinator = PackageDownloadCoordinator.shared
        let items = coordinator.downloaders.filter { ids.contains($0.model.id) }
        return DownloadProgress(items.map { .init(id: $0.model.id, expected: $0.model.byteCount, received: $0.state.receivedBytes, phase: $0.state.phase, ready: coordinator.downloadReady($0), packageFailed: coordinator.downloadPackageFailed($0)) })
    }
    private static func snapshot(_ input: DownloadProgress? = nil) -> DownloadActivityAttributes.ContentState {
        let items = PackageDownloadCoordinator.shared.downloaders.filter { ids.contains($0.model.id) }
        let progress = input ?? aggregateProgress()
        let title: String
        switch progress.status {
        case .ready: title = L10n.text("Пакеты для перевода готовы")
        case .verifying: title = L10n.text("Проверяю файлы…")
        case .failed: title = L10n.text("Загрузка прервана. Можно продолжить.")
        case .paused: title = L10n.text("Пауза")
        case .cancelled: title = L10n.text("Загрузка отменена")
        case .downloading: title = L10n.text("Загрузка моделей")
        }
        let names = Array(Set(items.map { $0.model.title })).sorted()
        let detail = names.prefix(2).joined(separator: " · ") + (names.count > 2 ? " +" + String(names.count - 2) : "")
        let format = ByteCountFormatter(); format.countStyle = .decimal
        return .init(title: title, detail: detail,
                     bytes: format.string(fromByteCount: progress.received) + " / " + format.string(fromByteCount: progress.total),
                     fraction: progress.fraction,
                     symbol: progress.status == .ready ? "checkmark.circle.fill" : progress.status == .failed ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.down.circle.fill",
                     finished: progress.finished)
    }
}
