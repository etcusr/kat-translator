import Foundation
import OfflineCore

extension PackageDownloadCoordinator {
    func removeRetiredTranslationModels() async {
        let defaults = UserDefaults.standard
        let migration = "removedGemmaMiLQwenTranslationV1"
        guard !defaults.bool(forKey: migration) else { return }
        for id in RetiredTranslationModels.ids {
            let configuration = URLSessionConfiguration.background(withIdentifier: ModelDownloader.sessionID + "." + id)
            let session = URLSession(configuration: configuration, delegate: RetiredDownloadDelegate(), delegateQueue: nil)
            for task in await session.allTasks { task.cancel() }
            session.invalidateAndCancel()
        }
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try RetiredTranslationModels.removeFiles(root: ModelDownloader.root, documents: documents)
            defaults.set(true, forKey: migration)
        } catch {
            // Retry on the next launch if storage was inaccessible.
            reportRetiredTranslationError(error)
        }
    }

    func removeRetiredThaiVoice() async {
        // Reconnect only to cancel old transfers; never restore or verify retired weights.
        for id in RetiredThaiVoice.ids {
            let configuration = URLSessionConfiguration.background(withIdentifier: ModelDownloader.sessionID + "." + id)
            let session = URLSession(configuration: configuration, delegate: RetiredDownloadDelegate(), delegateQueue: nil)
            for task in await session.allTasks { task.cancel() }
            session.invalidateAndCancel()
        }
        do {
            try RetiredThaiVoice.removeFiles(root: ModelDownloader.root)
        } catch {
            reportRetiredVoiceError(error)
        }
        let defaults = UserDefaults.standard
        if let old = defaults.string(forKey: "voice.th"), RetiredThaiVoice.ids.contains(old) {
            defaults.set(ModelCatalog.wayuVoice.id, forKey: "voice.th")
        }
        if let pending = defaults.stringArray(forKey: "pendingVoiceIDs") {
            defaults.set(pending.filter { !RetiredThaiVoice.ids.contains($0) }, forKey: "pendingVoiceIDs")
        }
    }
}

private final class RetiredDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Retired downloads are discarded; URLSession cleans its temporary file.
    }
}

extension PackageDownloadCoordinator {
    func removeRetiredWhisperKit() async {
        let defaults = UserDefaults.standard
        let migration = "removedWhisperKitV1"
        guard !defaults.bool(forKey: migration) else { return }
        // Cancel system-owned transfers before removing their exact package files.
        for id in RetiredWhisperKit.partIDs {
            let configuration = URLSessionConfiguration.background(withIdentifier: ModelDownloader.sessionID + "." + id)
            let session = URLSession(configuration: configuration, delegate: RetiredDownloadDelegate(), delegateQueue: nil)
            for task in await session.allTasks { task.cancel() }
            session.invalidateAndCancel()
        }
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try RetiredWhisperKit.removeFiles(root: ModelDownloader.root, documents: documents)
            if let pending = defaults.stringArray(forKey: "pendingRecognitionPackages") {
                defaults.set(pending.filter { $0 != RetiredWhisperKit.id }, forKey: "pendingRecognitionPackages")
            }
            defaults.set(true, forKey: migration)
        } catch {
            // Leave the migration pending so a later launch can finish removing inaccessible files.
            reportRetiredRecognitionError(error)
        }
    }
}
