import Foundation

public enum RecognitionChunks {
    /// Non-overlapping pieces, no longer than 20 seconds, cut at a quiet window near the end.
    public static func ranges(samples: [Float], sampleRate: Int) -> [Range<Int>] {
        guard sampleRate > 0, !samples.isEmpty else { return [] }
        let maximum = sampleRate * 20, search = sampleRate * 2, window = max(1, sampleRate / 20)
        var result: [Range<Int>] = [], start = 0
        while start < samples.count {
            var end = min(samples.count, start + maximum)
            if end < samples.count {
                var bestEnergy = Double.infinity
                for position in stride(from: end - search, through: end - window, by: window) {
                    let energy = samples[position..<(position + window)].reduce(0.0) { $0 + Double($1) * Double($1) }
                    if energy < bestEnergy { bestEnergy = energy; end = position + window / 2 }
                }
            }
            result.append(start..<end); start = end
        }
        return result
    }
}
