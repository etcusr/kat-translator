import Foundation

public enum SpeechLoudness {
    /// Raise quiet speech toward -16 dBFS active RMS, with at most +12 dB of gain.
    /// Ignore silent windows when choosing gain and soften peaks below -1 dBFS to leave AAC encoding headroom.
    public static func normalize(_ pcm: SpeechPCM) -> SpeechPCM {
        guard let gain = gain(for: pcm.samples, sampleRate: pcm.sampleRate) else { return pcm }
        return SpeechPCM(samples: pcm.samples.map { adjusted($0, gain: gain) }, sampleRate: pcm.sampleRate)
    }
    /// One gain for the entire recording prevents audible changes between encoding buffers.
    /// Split analysis from application so long microphone recordings need no full-size output copy.
    static func gain(for samples: [Float], sampleRate: Int) -> Double? {
        guard sampleRate > 0, !samples.isEmpty, samples.allSatisfy(\.isFinite) else { return nil }
        let window = max(1, sampleRate / 50)
        var energy = 0.0, activeSamples = 0
        for start in stride(from: 0, to: samples.count, by: window) {
            let end = min(samples.count, start + window)
            let sum = samples[start..<end].reduce(0.0) { $0 + Double($1) * Double($1) }
            if sum / Double(end-start) > 0.000025 { energy += sum; activeSamples += end-start }
        }
        guard activeSamples > 0, energy > 0 else { return nil }
        return min(4, max(1, 0.16 / sqrt(energy / Double(activeSamples))))
    }
    /// Microphone recordings can be much quieter than synthesized speech. Analyze
    /// their envelope separately; never apply this gain to recognition input.
    static func recordingGain(for samples: [Float], sampleRate: Int) -> Double? {
        guard sampleRate > 0, !samples.isEmpty, samples.allSatisfy(\.isFinite) else { return nil }
        let window = max(1, sampleRate / 50)
        var windows: [(power: Double, count: Int)] = []
        for start in stride(from: 0, to: samples.count, by: window) {
            let end = min(samples.count, start + window)
            let sum = samples[start..<end].reduce(0.0) { $0 + Double($1) * Double($1) }
            windows.append((sum / Double(end - start), end - start))
        }
        // Ignore long pauses before taking percentiles. Require at least 100 ms
        // above the floor so one isolated click cannot make silence loud.
        let sorted = windows.map(\.power).filter { $0 > 0.0000001 }.sorted()
        guard sorted.count >= 5 else { return nil }
        let reference = sorted[(sorted.count - 1) * 90 / 100]
        // Do not turn silence or a near-silent noise floor into loud playback.
        guard reference > 0.000001 else { return nil }
        let gate = max(0.0000001, reference * 0.01)
        // A handling click must not determine the gain for the surrounding voice.
        // Peaks are still preserved in the output and pass through the soft limiter.
        let ceiling = sorted[(sorted.count - 1) * 99 / 100]
        var energy = 0.0, count = 0
        for part in windows where part.power >= gate && part.power <= ceiling {
            energy += part.power * Double(part.count); count += part.count
        }
        guard count > 0, energy > 0 else { return nil }
        let gain = min(100, max(1, 0.16 / sqrt(energy / Double(count))))
        return gain > 1.01 ? gain : nil
    }
    /// Strongly amplified handling transients need more AAC headroom than TTS.
    static func recordingAdjusted(_ sample: Float, gain: Double) -> Float {
        let value = Double(sample) * gain, magnitude = abs(value)
        let limited = magnitude <= 0.55 ? magnitude : 0.55 + 0.15 * tanh((magnitude - 0.55) / 0.15)
        return Float(value < 0 ? -min(0.70, limited) : min(0.70, limited))
    }
    static func adjusted(_ sample: Float, gain: Double) -> Float {
        let value = Double(sample) * gain, magnitude = abs(value)
        let limited = magnitude <= 0.75 ? magnitude : 0.75 + 0.14 * tanh((magnitude - 0.75) / 0.14)
        return Float(value < 0 ? -min(0.89, limited) : min(0.89, limited))
    }
}
