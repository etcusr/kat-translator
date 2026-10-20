// Framework doubles only; DownloadLiveActivity and DownloadProgress are compiled unchanged.
let testDefaults = UserDefaults(suiteName: "KatActivityTests-" + UUID().uuidString)!
protocol ActivityAttributes {}
enum CatCoat: CaseIterable { case tabby }
enum L10n { static func text(_ value: String) -> String { value } }
public enum TransferPhase: Sendable { case downloading, checking, installed, failed, restartRequired, paused, cancelled }
struct Model { var id = "fixture"; var title = "Fixture"; var byteCount: Int64 = 100 }
struct State { var receivedBytes: Int64 = 0; var phase = TransferPhase.downloading }
@MainActor final class Downloader { var model = Model(); var state = State(); var ready = false }
@MainActor final class PackageDownloadCoordinator {
    static let shared = PackageDownloadCoordinator()
    var downloaders = [Downloader()]
    func downloadReady(_ item: Downloader) -> Bool { item.ready }
    func downloadPackageFailed(_ item: Downloader) -> Bool { false }
}
@MainActor final class UIApplication {
    static let shared = UIApplication()
    enum State { case active, background }
    var applicationState = State.active
}
@MainActor struct ActivityAuthorizationInfo { var areActivitiesEnabled = true }
@MainActor final class DownloadBackgroundWork { func end() {} }
struct ActivityContent<State> { var state: State; var staleDate: Date? }
enum ActivityState { case active, stale, ended }
enum DismissalPolicy { case after(Date) }
@MainActor final class Activity<Attributes> {
    // Swift disallows generic static stored properties; the registry is outside the double.
    static var activities: [Activity<Attributes>] { registry.compactMap { $0 as? Activity<Attributes> } }
    var activityState = ActivityState.active
    var updates: [DownloadActivityAttributes.ContentState] = []
    var blockNext = false
    var blocked: CheckedContinuation<Void, Never>?
    static func request(attributes: Attributes, content: ActivityContent<DownloadActivityAttributes.ContentState>, pushType: String?) throws -> Activity {
        let activity = Activity(); registry.append(activity); return activity
    }
    func update(_ content: ActivityContent<DownloadActivityAttributes.ContentState>) async {
        if blockNext {
            blockNext = false
            await withCheckedContinuation { blocked = $0 }
        }
        updates.append(content.state)
    }
    func end(_ content: ActivityContent<DownloadActivityAttributes.ContentState>, dismissalPolicy: DismissalPolicy) async {
        updates.append(content.state); activityState = .ended
    }
}
@MainActor var registry: [Any] = []

@main struct Probe {
    @MainActor static func main() async {
        // No activity: background completion must not hang or start one.
        await DownloadLiveActivity.flush()
        precondition(registry.isEmpty)
        DownloadLiveActivity.started("fixture")
        let activity = Activity<DownloadActivityAttributes>.activities[0]
        let item = PackageDownloadCoordinator.shared.downloaders[0]
        item.state.receivedBytes = 10
        await DownloadLiveActivity.flush()
        precondition(activity.updates.last?.fraction == 0.1)

        // Simulate a publication still in flight when a background event arrives.
        activity.blockNext = true
        item.state.receivedBytes = 20
        DownloadLiveActivity.changed()
        while activity.blocked == nil { await Task.yield() }
        item.state.receivedBytes = 31
        var completed = false
        let event = Task { await DownloadLiveActivity.flush(); completed = true }
        for _ in 0..<20 { await Task.yield() }
        precondition(!completed, "Background completion escaped before ActivityKit update")
        activity.blocked?.resume(); activity.blocked = nil
        await event.value
        precondition(activity.updates.last?.fraction == 0.31, "Flush returned with stale in-flight snapshot")

        item.state.receivedBytes = 100; item.state.phase = .installed; item.ready = true
        await DownloadLiveActivity.flush()
        precondition(activity.activityState == .ended)
        precondition(activity.updates.last?.finished == true)
        precondition(activity.updates.last?.fraction == 1)
        print("PASS: publication ordering, latest revision, completion")
    }
}
