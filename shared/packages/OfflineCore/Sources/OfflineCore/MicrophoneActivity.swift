import Foundation

/// Read-only display measurement. Never gates capture, VAD or phrase boundaries.
public struct MicrophoneActivity: Equatable, Sendable {
    public let level: Double
    public let speechDetected: Bool
    public static let quiet = MicrophoneActivity(samples: [], speechDetected: false)

    public init(samples: [Float], speechDetected: Bool) {
        var energy = 0.0
        for sample in samples where sample.isFinite {
            let value = min(1, max(-1, Double(sample)))
            energy += value * value
        }
        let rms = sqrt(energy / Double(max(1, samples.count)))
        // -60…-12 dBFS keeps quiet speech visible without inflating background silence.
        level = min(1, max(0, (20 * log10(max(rms, 0.000_001)) + 60) / 48))
        self.speechDetected = speechDetected
    }
}
