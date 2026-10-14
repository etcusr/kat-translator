#if DOWNLOAD_VALIDATION
import Foundation
import UIKit
import ActivityKit
import OfflineCore

/// Opt-in integration fixture. Never included in normal generated projects.
@MainActor enum DownloadValidationProbe {
    static var items: [ModelDownloader] = []
    static func run(progress: @escaping (String) -> Void) async {
        var report: [String: Any] = [:]
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("download-validation.json")
        func save() { if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output, options: .atomic) } }
        do {
            let parts = RecognitionPackages.definitions.first { $0.id == RecognitionCatalog.ultraID }!.parts.filter { ["Decoder.mlmodelc/weights/weight.bin", "JointDecisionv3.mlmodelc/weights/weight.bin"].contains($0.path) }
            items = parts.enumerated().map { index, part in
                ModelDownloader(model: ModelDescriptor(id: "download-validation-\(index)", title: "Download validation \(index + 1)", remoteURL: part.remoteURL, byteCount: part.byteCount, sha256: part.sha256))
            }
            if ProcessInfo.processInfo.environment["OT_DOWNLOAD_VALIDATION"] == "cleanup" {
                for item in items {
                    await item.restore(); await item.cancel()
                    try await item.store.remove(item.model)
                    try? FileManager.default.removeItem(at: item.transferRoot)
                }
                for activity in Activity<DownloadActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                UserDefaults.standard.removeObject(forKey: "liveDownloadIDs")
                progress("download-probe-cleaned")
                return
            }
            for item in items {
                await item.restore(); await item.cancel()
                if item.installedURL != nil { await item.remove() }
                try? await item.store.remove(item.model)
                await item.clearInstalledReference()
            }
            let first = items[0]
            first.start()
            let until = Date().addingTimeInterval(90)
            while first.state.receivedBytes < 262_144 && first.state.phase == .downloading && Date() < until { try await Task.sleep(for: .milliseconds(25)) }
            report["beforePauseBytes"] = first.state.receivedBytes
            await first.pause()
            report["pausePhase"] = first.state.phase.rawValue
            guard first.state.phase == .paused else { throw NSError(domain: "DownloadProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Resume data unavailable or transfer already finished"]) }
            let received = first.state.receivedBytes
            first.start(resuming: true)
            report["resumePreservedBytes"] = first.state.receivedBytes == received
            items[1].start()
            report["activityCount"] = Activity<DownloadActivityAttributes>.activities.count
            progress("download-probe-running"); save()
            let deadline = Date().addingTimeInterval(180)
            while items.contains(where: { $0.installedURL == nil }) && Date() < deadline {
                if items.contains(where: { [.failed, .restartRequired].contains($0.state.phase) }) { throw NSError(domain: "DownloadProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Transfer failed"]) }
                try await Task.sleep(for: .milliseconds(200))
            }
            report["verifiedFiles"] = items.filter { $0.installedURL != nil }.count
            report["finishedInBackground"] = UIApplication.shared.applicationState == .background
            report["phases"] = items.map { $0.state.phase.rawValue }
            report["bytes"] = items.map { $0.state.receivedBytes }
            save(); DownloadLiveActivity.changed()
            progress("download-probe-complete")
        } catch { report["error"] = error.localizedDescription; save(); progress("download-probe-error") }
    }
}
#endif
