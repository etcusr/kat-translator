import SwiftUI
import AVFoundation
import AppKit

struct CatWizardView: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    func makeNSView(context: Context) -> MacWizardSurface { MacWizardSurface() }
    func updateNSView(_ view: MacWizardSurface, context: Context) {
        view.setRunning(!reduceMotion && scenePhase == .active)
    }
    static func dismantleNSView(_ view: MacWizardSurface, coordinator: ()) { view.dispose() }
}

/// Show the poster immediately, including for very short jobs and Reduce Motion.
final class MacWizardSurface: NSView {
    private let playback = LoadingAnimationPlayback()
    private let videoLayer = AVPlayerLayer()
    private let poster = NSImageView()
    private var observation: NSKeyValueObservation?
    private var running = false
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14; layer?.masksToBounds = true
        layer?.addSublayer(videoLayer)
        videoLayer.videoGravity = .resizeAspect
        videoLayer.player = playback.player
        poster.imageScaling = .scaleProportionallyUpOrDown
        if let clip = playback.animation { setPoster(clip) }
        playback.onAnimationChange = { [weak self] clip in self?.setPoster(clip) }
        addSubview(poster)
        observation = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updatePoster() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds; poster.frame = bounds
        CATransaction.commit()
    }
    func setRunning(_ value: Bool) {
        guard running != value else { updatePoster(); return }
        running = value
        playback.setRunning(value)
        updatePoster()
    }
    private func setPoster(_ clip: LoadingAnimation) {
        poster.image = clip.posterURL.flatMap { NSImage(contentsOf: $0) }
        poster.isHidden = false
    }
    private func updatePoster() { poster.isHidden = running && videoLayer.isReadyForDisplay }
    func dispose() {
        observation?.invalidate(); observation = nil
        playback.dispose(); videoLayer.player = nil
    }
}
