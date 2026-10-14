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
    var body: some Scene {
        WindowGroup {
            ConversationView(model: model)
                .task { delegate.model = model; await model.prepare() }
                .onChange(of: scenePhase) { _, phase in if phase == .background { model.background() } else if phase == .active { Task { await model.history.refresh(); await model.loadAutomaticallyIfNeeded() } } }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await model.memoryWarning() }
                }
        }
    }
}
