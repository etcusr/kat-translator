import Foundation
struct PreparedSpeech: Sendable {
    let text: String
    let pcm: SpeechPCM
    let synthesisSeconds: Double
    let removedSilenceSeconds: Double
}
@MainActor final class SpeechPreparation {
    private var parts: [String]
    private var index = 0
    private let speech: any SpeechSynthesisBackend
    init(text: String, speech: any SpeechSynthesisBackend) throws {
        self.speech = speech
        parts = try TextSegments.split(text) { $0.count <= 180 }
        if let first = parts.first, first.count > 90 {
            parts.replaceSubrange(0...0, with: try TextSegments.split(first) { $0.count <= 90 })
        }
    }
    func next() async throws -> PreparedSpeech? {
        let start = ProcessInfo.processInfo.systemUptime
        while index < parts.count {
            try Task.checkCancellation()
            let text = parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { index += 1; continue }
            let pcm: SpeechPCM
            do { pcm = try await speech.synthesize(text: text) }
            catch PipelineError.tooLong {
                let split = try TextSegments.bisect(parts[index]); parts.replaceSubrange(index...index, with: [split.0, split.1]); continue
            }
            try Task.checkCancellation()
            guard pcm.sampleRate > 0, !pcm.samples.isEmpty, pcm.samples.allSatisfy(\.isFinite), pcm.samples.count <= pcm.sampleRate * 60 else { throw PipelineError.invalidAudio }
            index += 1
            let compact = await Task.detached(priority: .userInitiated) { SpeechLoudness.normalize(SpeechSilenceLimiter.compact(pcm)) }.value
            try Task.checkCancellation()
            return PreparedSpeech(text: text, pcm: compact, synthesisSeconds: ProcessInfo.processInfo.systemUptime - start,
                removedSilenceSeconds: Double(pcm.samples.count - compact.samples.count) / Double(pcm.sampleRate))
        }
        return nil
    }
}
