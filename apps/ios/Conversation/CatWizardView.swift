import SwiftUI
import AVFoundation
import UIKit

/// Silent local shuffle, only while waiting. No audio-session changes or progress estimate.
struct CatWizardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        WizardVideo(running: !reduceMotion && scenePhase == .active)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

private struct WizardVideo: UIViewRepresentable {
    let running: Bool
    func makeUIView(context: Context) -> WizardVideoSurface { WizardVideoSurface() }
    func updateUIView(_ view: WizardVideoSurface, context: Context) { view.setRunning(running) }
    static func dismantleUIView(_ view: WizardVideoSurface, coordinator: ()) { view.dispose() }
}

private final class WizardVideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let playback = LoadingAnimationPlayback()
    private var readyObservation: NSKeyValueObservation?
    private let poster = UIImageView()
    private var running: Bool?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        poster.contentMode = .scaleAspectFit
        if let clip = playback.animation { setPoster(clip) }
        playback.onAnimationChange = { [weak self] clip in self?.setPoster(clip) }
        addSubview(poster)
        videoLayer.videoGravity = .resizeAspect
        videoLayer.player = playback.player
        readyObservation = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            // KVO delivery can occur outside the main thread.
            Task { @MainActor [weak self] in self?.updatePoster() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); poster.frame = bounds }
    func setRunning(_ value: Bool) {
        guard running != value else { return }
        running = value
        if value { RecordingStopTrace.mark("wizard.video.play") }
        playback.setRunning(value)
        updatePoster()
    }
    private func setPoster(_ clip: LoadingAnimation) {
        poster.image = clip.posterURL.flatMap { UIImage(contentsOfFile: $0.path) }
        poster.isHidden = false
    }
    private func updatePoster() {
        if running == true && videoLayer.isReadyForDisplay { RecordingStopTrace.mark("wizard.video.ready") }
        poster.isHidden = running == true && videoLayer.isReadyForDisplay
    }
    func dispose() {
        readyObservation?.invalidate(); readyObservation = nil
        playback.dispose(); videoLayer.player = nil
    }
}
