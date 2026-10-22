import SwiftUI
import OfflineCore

/// Meter updates invalidate only the decoration/status, never conversation layout.
@MainActor final class MicrophoneActivityState: ObservableObject {
    @Published private(set) var value = MicrophoneActivity.quiet
    @Published private(set) var levels = Array(repeating: 0.0, count: 25)
    func update(_ next: MicrophoneActivity) {
        if next != value { value = next }
        // A short history of measured loudness, not simulated frequency bands.
        if next == .quiet {
            if levels.contains(where: { $0 != 0 }) { levels = Array(repeating: 0, count: 25) }
        } else {
            levels = Array(levels.dropFirst()) + [next.level]
        }
    }
}

struct MicrophoneActivityBackdrop: View {
    @ObservedObject var activity: MicrophoneActivityState
    let paused: Bool
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MicrophoneActivityBarsDisplay(levels: activity.levels, paused: paused,
                                      reduceMotion: reduceMotion, diameter: diameter)
    }
}

struct MicrophoneActivityBarsDisplay: View {
    let levels: [Double]
    let paused: Bool
    let reduceMotion: Bool
    let diameter: CGFloat
    var body: some View {
        HStack(spacing: diameter * 0.034) {
            ForEach(levels.indices, id: \.self) { index in
                let level = paused ? 0 : min(1, max(0, levels[index]))
                Capsule()
                    .fill(KatTheme.accent.opacity(paused ? 0.07 : 0.10 + level * 0.38))
                    .frame(width: diameter * 0.055,
                           height: diameter * (reduceMotion ? 0.3 : 0.045 + level * 0.92))
            }
        }
        .frame(width: diameter * 2.2, height: diameter)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                    .init(color: .white, location: 0.12),
                                    .init(color: .white, location: 0.88),
                                    .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .animation(reduceMotion || paused ? nil : .easeOut(duration: 0.14), value: levels)
        // Decoration can extend outside the fixed button slot without moving controls.
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MicrophoneActivityStatus: View {
    @ObservedObject var activity: MicrophoneActivityState
    let paused: Bool
    let status: String
    private var stateLabel: String {
        if paused { return L10n.text("Запись на паузе") }
        if activity.value.speechDetected { return L10n.text("Слышу речь") }
        return activity.value.level > 0.08 ? L10n.text("Слышу звук") : L10n.text("Тихо")
    }
    var body: some View {
        Text(status).font(.system(size: 17, weight: .medium))
            .accessibilityLabel(status + ": " + L10n.text("Активность микрофона") + ", " + stateLabel)
            .accessibilityIdentifier("voice.processing.status")
    }
}
