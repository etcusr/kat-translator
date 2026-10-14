import Foundation
import OfflineCore
import SpeechRecognitionRuntime

/// Cancellation reaches the actual worker, and unloading waits for its last inference.
final class CoreMLRecognitionBackend: ASRBackend, @unchecked Sendable {
    private let worker = CoreMLRecognitionWorker()
    private let lock = NSLock()
    private var active: Task<OfflineCore.ASRResult, Error>?
    func load(modelURL: URL) async throws { try await worker.load(modelURL) }
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> OfflineCore.ASRResult {
        try Task.checkCancellation()
        let task = Task { try await worker.transcribe(audio, language: language) }
        setActive(task)
        defer { setActive(nil) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func setActive(_ task: Task<OfflineCore.ASRResult, Error>?) { lock.lock(); active = task; lock.unlock() }
    private func current() -> Task<OfflineCore.ASRResult, Error>? { lock.lock(); defer { lock.unlock() }; return active }
    func cancel() { current()?.cancel() }
    func unload() async { let task = current(); task?.cancel(); _ = try? await task?.value; await worker.unload() }
}

private actor CoreMLRecognitionWorker {
    private var ultra: AsrManager?
    func load(_ url: URL) async throws {
        SpeechMemoryTrace.record("asr-load-start", model: url.lastPathComponent)
        await unload()
        SpeechMemoryTrace.record("asr-unload-complete", model: url.lastPathComponent)
        do {
            guard url.lastPathComponent == RecognitionCatalog.ultraID else { throw PipelineError.modelLoad }
            AppLogger.minimumLevel = .error; AppLogger.mirrorsToConsole = false
            let models = try await Task.detached(priority: .userInitiated) { try AsrModels.loadLocal(from: url, version: .ultra) }.value
            SpeechMemoryTrace.record("asr-local-models-ready", model: url.lastPathComponent)
            try Task.checkCancellation()
            let manager = AsrManager(); ultra = manager
            try await manager.loadModels(models)
            try Task.checkCancellation()
            SpeechMemoryTrace.record("asr-load-ready", model: url.lastPathComponent)
        } catch { await unload(); throw error }
    }
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> OfflineCore.ASRResult {
        try Task.checkCancellation()
        guard !audio.samples.isEmpty else { throw PipelineError.noSpeech }
        let start = ProcessInfo.processInfo.systemUptime
        var text = ""
        var detected = language
        if let ultra {
            guard RecognitionCatalog.prefersUltra(language) else { throw PipelineError.recognitionUnavailable }
            // Keep tested whole-recording decoding for conversational clips; bound very long
            // input and cancellation latency without asking CoreML to batch ten minutes at once.
            let ranges = audio.samples.count <= 60 * 16000 ? [0..<audio.samples.count] : RecognitionChunks.ranges(samples: audio.samples, sampleRate: 16000)
            var pieces: [String] = []
            for range in ranges {
                try Task.checkCancellation()
                var state = try TdtDecoderState()
                let result = try await ultra.transcribe(Array(audio.samples[range]), decoderState: &state)
                pieces.append(result.text)
            }
            text = pieces.joined(separator: " ")
            // Ultra emits multilingual text, not a language ID; identify its text locally.
            if detected == nil { detected = TextLanguageDetection.detect(text) }
        } else { throw PipelineError.modelLoad }
        try Task.checkCancellation()
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PipelineError.noSpeech }
        guard let detected else { throw PipelineError.unsupportedLanguage }
        return OfflineCore.ASRResult(text: text, language: detected, processingSeconds: ProcessInfo.processInfo.systemUptime - start, engineID: RecognitionCatalog.ultraID)
    }
    func unload() async { await ultra?.cleanup(); ultra = nil }
}
