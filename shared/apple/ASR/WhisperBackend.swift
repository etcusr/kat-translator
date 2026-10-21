import Foundation
import OfflineCore

private final class WhisperFlag: @unchecked Sendable {
    let pointer: OpaquePointer
    init() throws {
        guard let pointer = wt_cancel_create() else { throw WhisperError.allocation }
        self.pointer = pointer
    }
    func cancel() { wt_cancel_set(pointer) }
    var cancelled: Bool { wt_abort(UnsafeMutableRawPointer(pointer)) }
    deinit { wt_cancel_free(pointer) }
}
enum WhisperError: LocalizedError {
    case allocation, load, noModel, inference(Int32), noSpeech
    var errorDescription: String? {
        switch self {
        case .allocation: return L10n.text("Недостаточно памяти.")
        case .load: return L10n.text("Не удалось загрузить Whisper. Освободите память и повторите.")
        case .noModel: return L10n.text("Сначала загрузите модель в память.")
        case .inference(let code): return L10n.text("Распознавание завершилось с ошибкой \(code).")
        case .noSpeech: return L10n.text("Речь не обнаружена. Попробуйте записать реплику снова.")
        }
    }
}
final class WhisperBackend: ASRBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openoffline.whisper", qos: .userInitiated)
    private var context: OpaquePointer?
    private let lock = NSLock()
    private var activeFlag: WhisperFlag?
    func load(modelURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if let context = self.context { whisper_free(context); self.context = nil }
                // Do not write model output or intermediate tokens into system logs.
                whisper_log_set({ _, _, _ in }, nil)
                var params = whisper_context_default_params()
                params.use_gpu = true
                self.context = whisper_init_from_file_with_params(modelURL.path, params)
                if self.context == nil { continuation.resume(throwing: WhisperError.load) }
                else { continuation.resume() }
            }
        }
    }
    func transcribe(_ audio: CapturedAudio, language: SpeechLanguage?) async throws -> ASRResult {
        try Task.checkCancellation()
        if let language, language.whisperCode == nil { throw PipelineError.recognitionUnavailable }
        guard !audio.samples.isEmpty else { throw WhisperError.noSpeech }
        let repairDateTime = WhisperDateTimeRepair.isEnabled()
        let flag = try WhisperFlag()
        setActive(flag)
        defer { clearActive(flag) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !flag.cancelled else { continuation.resume(throwing: CancellationError()); return }
                    guard let context = self.context else { continuation.resume(throwing: WhisperError.noModel); return }
                    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                    params.translate = false; params.no_context = true
                    // "auto" detects and transcribes; detect_language=true would return without transcription.
                    params.detect_language = false
                    params.print_realtime = false; params.print_progress = false
                    params.print_timestamps = false; params.print_special = false
                    params.temperature = 0; params.temperature_inc = 0
                    params.n_threads = Int32(min(4, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)))
                    params.abort_callback = wt_abort
                    params.abort_callback_user_data = UnsafeMutableRawPointer(flag.pointer)
                    let start = ProcessInfo.processInfo.systemUptime
                    let code = (language?.whisperCode ?? "auto").withCString { lang in
                        params.language = lang
                        return audio.samples.withUnsafeBufferPointer { samples in
                            whisper_full(context, params, samples.baseAddress, Int32(samples.count))
                        }
                    }
                    if flag.cancelled { continuation.resume(throwing: CancellationError()); return }
                    guard code == 0 else { continuation.resume(throwing: WhisperError.inference(code)); return }
                    let detectedLanguage: SpeechLanguage
                    if let language { detectedLanguage = language }
                    else {
                        guard let code = whisper_lang_str(whisper_full_lang_id(context)),
                              let detected = SpeechLanguage.allCases.first(where: { $0.whisperCode == String(cString: code) }) else {
                            continuation.resume(throwing: PipelineError.unsupportedLanguage); return
                        }
                        detectedLanguage = detected
                    }
                    func transcript() -> String {
                        var value = ""
                        for index in 0..<whisper_full_n_segments(context) {
                            if let segment = whisper_full_get_segment_text(context, index) { value += String(cString: segment) }
                        }
                        return value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    var text = transcript()
                    let originalText = text
                    // Whisper timestamps are in 10 ms units; retain the primary pass
                    // before the optional date/time retry replaces native segment state.
                    let segments = (0..<whisper_full_n_segments(context)).compactMap { index -> ASRSegment? in
                        guard let value = whisper_full_get_segment_text(context, index) else { return nil }
                        return ASRSegment(text: String(cString: value), endSample: Int(whisper_full_get_segment_t1(context, index)) * 160)
                    }
                    // Only retry a short Russian clip with an ambiguous time/date triple.
                    // The original remains authoritative unless acoustic word evidence agrees.
                    if audio.samples.count <= 30 * 16_000,
                       WhisperDateTimeRepair.needsRetry(text, language: detectedLanguage, enabled: repairDateTime) {
                        params.no_timestamps = true // Digit suppression must not suppress timestamp tokens.
                        params.max_tokens = 256 // A truncated retry fails word agreement and keeps the original.
                        let retryCode = "ru".withCString { lang in
                            params.language = lang
                            return ".*[0-9].*".withCString { pattern in
                                params.suppress_regex = pattern
                                return audio.samples.withUnsafeBufferPointer { samples in
                                    whisper_full(context, params, samples.baseAddress, Int32(samples.count))
                                }
                            }
                        }
                        if flag.cancelled { continuation.resume(throwing: CancellationError()); return }
                        if retryCode == 0 { text = WhisperDateTimeRepair.repair(text, retry: transcript()) }
                    }
                    let result = ASRResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: detectedLanguage,
                        processingSeconds: ProcessInfo.processInfo.systemUptime - start, engineID: ModelDescriptor.turbo.id, segments: text == originalText ? segments : [])
                    continuation.resume(returning: result)
                }
            }
        } onCancel: { flag.cancel() }
    }
    private func setActive(_ flag: WhisperFlag) {
        lock.lock(); defer { lock.unlock() }; activeFlag = flag
    }
    private func clearActive(_ flag: WhisperFlag) {
        lock.lock(); defer { lock.unlock() }
        if activeFlag === flag { activeFlag = nil }
    }
    func cancel() { lock.lock(); activeFlag?.cancel(); lock.unlock() }
    func unload() async {
        cancel()
        await withCheckedContinuation { continuation in
            queue.async {
                if let context = self.context { whisper_free(context); self.context = nil }
                continuation.resume()
            }
        }
    }
    deinit { if let context { whisper_free(context) } }
}
