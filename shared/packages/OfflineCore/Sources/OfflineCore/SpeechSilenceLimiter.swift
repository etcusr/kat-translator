import Foundation
public enum SpeechSilenceLimiter {
    /// Only runs whose every sample is very quiet are shortened; retain guard audio at both edges.
    public static func compact(_ pcm: SpeechPCM) -> SpeechPCM {
        guard pcm.sampleRate > 0, !pcm.samples.isEmpty else { return pcm }
        let frame = max(1, pcm.sampleRate / 50)
        let cap = pcm.sampleRate
        let edge = max(1, pcm.sampleRate * 80 / 1000)
        let samples = pcm.samples
        var output: [Float] = []; output.reserveCapacity(samples.count)
        var position = 0
        while position < samples.count {
            let end = min(samples.count, position + frame)
            if samples[position..<end].allSatisfy({ abs($0) < 0.0015 }) {
                let start = position; position = end
                while position < samples.count {
                    let next = min(samples.count, position + frame)
                    guard samples[position..<next].allSatisfy({ abs($0) < 0.0015 }) else { break }
                    position = next
                }
                let length = position - start
                let keep = start == 0 || position == samples.count ? edge : cap
                if length <= keep { output.append(contentsOf: samples[start..<position]) }
                else {
                    let left = keep / 2
                    output.append(contentsOf: samples[start..<(start + left)])
                    output.append(contentsOf: samples[(position - (keep - left))..<position])
                }
            } else { output.append(contentsOf: samples[position..<end]); position = end }
        }
        return SpeechPCM(samples: output, sampleRate: pcm.sampleRate)
    }
}
