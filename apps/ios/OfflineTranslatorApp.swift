import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    var model: AppModel?
    func applicationWillTerminate(_ application: UIApplication) { model?.clearTemporaryAudio() }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard let downloader = PackageDownloadCoordinator.shared.downloaders.first(where: { $0.identifier == identifier }) else { completionHandler(); return }
        ModelDownloader.backgroundCompletions[identifier] = completionHandler
        Task { await downloader.restore() }
    }
}
@main struct OfflineTranslatorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Persistent ggml Metal residency can exhaust iOS's wired-memory budget:
        // CoreAudio then cannot mlock even its small I/O buffer (StartIO 'nope').
        // Keep models loaded, but let Metal manage residency during GPU work.
        // This flag must be set before the first ggml Metal device is created.
        setenv("GGML_METAL_NO_RESIDENCY", "1", 1)
    }
    var body: some Scene {
        WindowGroup {
            ConversationView(model: model)
                .task { delegate.model = model; await model.prepare() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        DownloadLiveActivity.refreshAfterLifecycleChange()
                        model.background()
                    } else if phase == .active {
                        DownloadLiveActivity.refreshAfterLifecycleChange()
                        Task { await model.history.refresh(); await model.loadAutomaticallyIfNeeded() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await model.memoryWarning() }
                }
        }
    }
}
