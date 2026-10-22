import SwiftUI
import AVFoundation
import OfflineCore

@MainActor final class HistoryModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    let store: TranslationHistory
    @Published private(set) var entries: [HistoryEntry] = []
    @Published var error: String?
    @Published private(set) var playingID: UUID?
    @Published private(set) var isPaused = false
    @Published private(set) var playbackSpeed = PlaybackSpeed.normal
    private var player: AVAudioPlayer?
    private var playbackURL: URL?
    private var generation = 0
    private var prepared = false
    private let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryExports")
    private let defaults: UserDefaults
    init(store: TranslationHistory, defaults: UserDefaults = .standard) { self.store = store; self.defaults = defaults; super.init() }
    /// Limits as currently edited; settings persist every slider step immediately.
    static func policy(in d: UserDefaults) -> HistoryPolicy {
        HistoryPolicy(textCount: d.object(forKey: "historyTextCount") == nil ? 100 : d.integer(forKey: "historyTextCount"),
            audioCount: d.object(forKey: "historyAudioCount") == nil ? 10 : d.integer(forKey: "historyAudioCount"),
            textDays: d.object(forKey: "historyTextDays") == nil ? 30 : d.integer(forKey: "historyTextDays"),
            audioDays: d.object(forKey: "historyAudioDays") == nil ? 30 : d.integer(forKey: "historyAudioDays"),
            imageCount: d.object(forKey: "historyImageCount") == nil ? 20 : d.integer(forKey: "historyImageCount"),
            imageDays: d.object(forKey: "historyImageDays") == nil ? 30 : d.integer(forKey: "historyImageDays"))
    }
    static let appliedPolicyKey = "historyAppliedPolicy"
    /// Pruning uses the limits confirmed by closing the settings: a scene activation while the
    /// slider passes "1 day" must not delete older history (audit 22.10, iOS M1).
    /// The first refresh (also after an update from a build without this key) confirms the limits then in effect.
    var appliedPolicy: HistoryPolicy {
        if let policy = defaults.data(forKey: Self.appliedPolicyKey).flatMap({ try? JSONDecoder().decode(HistoryPolicy.self, from: $0) }) { return policy }
        return confirmCurrentPolicy()
    }
    @discardableResult private func confirmCurrentPolicy() -> HistoryPolicy {
        let policy = Self.policy(in: defaults)
        if let data = try? JSONEncoder().encode(policy) { defaults.set(data, forKey: Self.appliedPolicyKey) }
        return policy
    }
    func confirmPolicy() async { confirmCurrentPolicy(); await refresh() }
    func applyRecordingSettings() async {
        let d = UserDefaults.standard
        await store.setRecording(text: d.object(forKey: "historyRecordText") as? Bool ?? true,
                                 audio: d.object(forKey: "historyRecordAudio") as? Bool ?? true,
                                 images: d.object(forKey: "historyRecordImages") as? Bool ?? true)
    }
    func refresh() async {
        await applyRecordingSettings()
        do {
            if !prepared { try? FileManager.default.removeItem(at: temporary); prepared = true }
            try await store.setPolicy(appliedPolicy); entries = try await store.list(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func clear() async {
        stopPlayback()
        do {
            try await store.removeAll()
            entries = try await store.list()
            if FileManager.default.fileExists(atPath: temporary.path) { try FileManager.default.removeItem(at: temporary) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ entry: HistoryEntry) async {
        if playingID == entry.id { stopPlayback() }
        do { try await store.remove(entry.id); await refresh() } catch { self.error = error.localizedDescription }
    }
    func imageURL(_ id: UUID) async -> URL? {
        do { return try await store.copyImage(id, into: temporary) }
        catch { self.error = error.localizedDescription; return nil }
    }
    func saveImage(_ png: Data, blocks: [TranslatedImageBlock], source: SpeechLanguage, target: SpeechLanguage) async throws {
        await applyRecordingSettings()
        _ = try await store.saveImage(png, original: blocks.map(\.original).joined(separator: "\n\n"),
            translation: blocks.map(\.translation).joined(separator: "\n\n"), source: source, target: target)
        await refresh()
    }
    func shareURL(_ id: UUID) async -> URL? {
        do { return try await store.copyAudio(id, into: temporary) }
        catch { self.error = error.localizedDescription; return nil }
    }
    func play(_ entry: HistoryEntry) async {
        if playingID == entry.id { stopPlayback(); return }
        stopPlayback(); generation += 1; let id = generation; playingID = entry.id
        guard let url = await shareURL(entry.id) else { playingID = nil; return }
        guard generation == id else { try? FileManager.default.removeItem(at: url); return }
        do {
        #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
        #if os(iOS)
            try AVAudioSession.sharedInstance().setActive(true)
        #endif
            let player = try AVAudioPlayer(contentsOf: url); player.delegate = self
            player.enableRate = true; player.rate = Float(playbackSpeed.rawValue)
            self.player = player; playbackURL = url
            guard player.play() else { throw PipelineError.invalidAudio }
        } catch { self.error = error.localizedDescription; stopPlayback() }
    }
    func stopPlayback() {
        isPaused = false
        generation += 1; player?.stop(); player = nil
        if let playbackURL { try? FileManager.default.removeItem(at: playbackURL) }
        playbackURL = nil
        #if os(iOS)
        if playingID != nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        #endif
        playingID = nil
    }
    func togglePause() {
        guard let player else { return }
        if isPaused {
            guard player.play() else { error = PipelineError.invalidAudio.localizedDescription; stopPlayback(); return }
            isPaused = false
        } else { player.pause(); isPaused = true }
    }
    func setPlaybackSpeed(_ speed: PlaybackSpeed) {
        playbackSpeed = speed; player?.rate = Float(speed.rawValue)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in if self?.player === player { self?.stopPlayback() } }
    }
}
struct SharedAudio: Identifiable { let id = UUID(); let url: URL }
#if os(iOS)
struct AudioShareSheet: UIViewControllerRepresentable {
    let item: SharedAudio
    let done: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in done() }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#endif
