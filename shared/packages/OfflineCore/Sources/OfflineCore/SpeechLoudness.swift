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
    static func adjusted(_ sample: Float, gain: Double) -> Float {
        let value = Double(sample) * gain, magnitude = abs(value)
        let limited = magnitude <= 0.75 ? magnitude : 0.75 + 0.14 * tanh((magnitude - 0.75) / 0.14)
        return Float(value < 0 ? -min(0.89, limited) : min(0.89, limited))
    }
}
