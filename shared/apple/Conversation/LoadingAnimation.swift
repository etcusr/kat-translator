import AVFoundation
import Foundation

struct LoadingAnimation: Decodable, Equatable {
    let id: String
    let resource: String
    let duration: Double

    var videoURL: URL? { Bundle.main.url(forResource: resource, withExtension: "mp4") }
    var posterURL: URL? {
        Bundle.main.url(forResource: resource == "cat-wizard" ? "cat-wizard-poster" : resource, withExtension: "jpg")
    }
    static let available: [Self] = {
        if let url = Bundle.main.url(forResource: "loading-animations", withExtension: "json"),
           let data = try? Data(contentsOf: url), let clips = try? JSONDecoder().decode([Self].self, from: data) {
            let usable = clips.filter { $0.duration.isFinite && $0.duration > 0 && $0.videoURL != nil && $0.posterURL != nil }
            if !usable.isEmpty { return usable }
        }
        return [Self(id: "wizard", resource: "cat-wizard", duration: 3.8)].filter { $0.videoURL != nil }
    }()
}

/// Shared shuffle bag: every clip gets a turn, including across separate waits.
@MainActor final class LoadingAnimationDeck {
    static let shared = LoadingAnimationDeck(animations: LoadingAnimation.available)
    private let animations: [LoadingAnimation]
    private var remaining: [LoadingAnimation] = []
    private var previous: String?

    init(animations: [LoadingAnimation]) { self.animations = animations }
    func next() -> LoadingAnimation? {
        if remaining.isEmpty {
            remaining = animations.shuffled()
            if remaining.count > 1, remaining.last?.id == previous {
                remaining.swapAt(0, remaining.count - 1)
            }
        }
        let result = remaining.popLast()
        previous = result?.id
        return result
    }
}

/// One muted decoder per visible animation. Rotate only at a clip boundary.
@MainActor final class LoadingAnimationPlayback {
    let player = AVPlayer()
    private(set) var animation: LoadingAnimation?
    private(set) var running = false
    var onAnimationChange: ((LoadingAnimation) -> Void)?
    private let deck: LoadingAnimationDeck
    private var endObservation: NSObjectProtocol?
    private var disposed = false

    init(deck: LoadingAnimationDeck? = nil) {
        self.deck = deck ?? .shared
        player.isMuted = true
        player.volume = 0
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause
        if let first = self.deck.next() { select(first) }
    }
    func setRunning(_ value: Bool) {
        guard !disposed, running != value else { return }
        running = value
        if value { player.play() } else { player.pause() }
    }
    private func select(_ clip: LoadingAnimation) {
        guard !disposed, let url = clip.videoURL else { return }
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
        animation = clip
        onAnimationChange?(clip)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        endObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item else { return }
                self.finished(item)
            }
        }
        if running { player.play() }
    }
    private func finished(_ item: AVPlayerItem) {
        guard !disposed, player.currentItem === item, let animation else { return }
        if let next = deck.next(), next.id != animation.id {
            select(next)
            return
        }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, !self.disposed, self.player.currentItem === item, self.running else { return }
                self.player.play()
            }
        }
    }
    func dispose() {
        disposed = true; running = false
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
        endObservation = nil; onAnimationChange = nil
        player.pause(); player.replaceCurrentItem(with: nil)
    }
    deinit {
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
    }
}
