import Foundation
import OfflineCore

/// Loads a single recognizer at a time. The pipeline selects the file for the requested language.
final class RoutedASRBackend: ASRBackend, @unchecked Sendable {
    private let whisper = WhisperBackend()
    private let omni = OmnilingualBackend()
    private let coreML = CoreMLRecognitionBackend()
    private var useCoreML = false
    private var useOmni = false
    func load(modelURL: URL) async throws {
        await unload()
        useCoreML = modelURL.lastPathComponent == RecognitionCatalog.ultraID
        useOmni = modelURL.hasDirectoryPath && !useCoreML
        if useCoreML { try await coreML.load(modelURL: modelURL) }
        else if useOmni { try await omni.load(modelURL: modelURL) }
        else { try await whisper.load(modelURL: modelURL) }
    }
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult {
        if useCoreML { return try await coreML.transcribe(audio, language: language) }
        if useOmni { return try await omni.transcribe(audio, language: language) }
        return try await whisper.transcribe(audio, language: language)
    }
    func cancel() { whisper.cancel(); omni.cancel(); coreML.cancel() }
    func unload() async { cancel(); await whisper.unload(); await omni.unload(); await coreML.unload() }
}

private final class RecognitionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
final class OmnilingualBackend: ASRBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.omnilingual", qos: .userInitiated)
    private var context: OpaquePointer?
    private let lock = NSLock()
    private var active: RecognitionCancellation?
    func load(modelURL: URL) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in queue.async {
            if let context = self.context { SherpaOnnxDestroyOfflineRecognizer(context); self.context = nil }
            self.context = ot_omni_create(modelURL.appendingPathComponent("model.int8.onnx").path,
                modelURL.appendingPathComponent("tokens.txt").path)
            if self.context == nil { c.resume(throwing: PipelineError.modelLoad) } else { c.resume() }
        } }
    }
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult {
        try Task.checkCancellation()
        guard let language, RecognitionCatalog.omnilingualCodes[language.rawValue] != nil else { throw PipelineError.recognitionUnavailable }
        guard !audio.samples.isEmpty else { throw PipelineError.noSpeech }
        let flag = RecognitionCancellation()
        setActive(flag)
        defer { setActive(nil) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in queue.async {
                do {
                    guard let context = self.context else { throw PipelineError.modelLoad }
                    let start = ProcessInfo.processInfo.systemUptime
                    var pieces: [String] = []
                    // Bound each synchronous ONNX decode; cancellation is observed between chunks.
                    for range in RecognitionChunks.ranges(samples: audio.samples, sampleRate: 16000) {
                        guard !flag.cancelled else { throw CancellationError() }
                        guard let stream = SherpaOnnxCreateOfflineStream(context) else { throw PipelineError.inference }
                        defer { SherpaOnnxDestroyOfflineStream(stream) }
                        audio.samples.withUnsafeBufferPointer {
                            SherpaOnnxAcceptWaveformOffline(stream, 16000, $0.baseAddress!.advanced(by: range.lowerBound), Int32(range.count))
                        }
                        SherpaOnnxDecodeOfflineStream(context, stream)
                        guard !flag.cancelled else { throw CancellationError() }
                        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { throw PipelineError.inference }
                        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
                        if let text = result.pointee.text {
                            let text = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty { pieces.append(text) }
                        }
                    }
                    guard !pieces.isEmpty else { throw PipelineError.noSpeech }
                    c.resume(returning: ASRResult(text: pieces.joined(separator: language == .lang_zh_Hant ? "" : " "), language: language,
                        processingSeconds: ProcessInfo.processInfo.systemUptime - start))
                } catch { c.resume(throwing: error) }
            } }
        } onCancel: { flag.cancel() }
    }
    private func setActive(_ flag: RecognitionCancellation?) { lock.lock(); active = flag; lock.unlock() }
    func cancel() { lock.lock(); active?.cancel(); lock.unlock() }
    func unload() async {
        cancel()
        await withCheckedContinuation { c in queue.async {
            if let context = self.context { SherpaOnnxDestroyOfflineRecognizer(context); self.context = nil }
            c.resume()
        } }
    }
    deinit { if let context { SherpaOnnxDestroyOfflineRecognizer(context) } }
}
