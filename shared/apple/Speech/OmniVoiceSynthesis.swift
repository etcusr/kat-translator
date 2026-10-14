import Foundation
import Darwin
import OfflineCore

/// Owned and used only on SherpaSpeechBackend's serial synthesis queue.
final class OmniVoiceSynthesis {
    private let context: OpaquePointer
    private let language: String
    init(directory: URL, language: String) throws {
        // Keep the translation model warm. Refuse an unsafe load instead of silently
        // evicting it or relying on a process termination to enforce iOS's budget.
        #if os(iOS)
        guard os_proc_available_memory() >= 1_500_000_000 else { throw OmniVoiceError.memory }
        #endif
        self.language = language
        var params = ov_init_params(); ov_init_default_params(&params)
        let model = directory.appendingPathComponent("omnivoice-base-Q8_0.gguf").path
        let codec = directory.appendingPathComponent("omnivoice-tokenizer-Q8_0.gguf").path
        let loaded = model.withCString { modelPath in codec.withCString { codecPath in
            params.model_path = modelPath; params.codec_path = codecPath
            return ov_init(&params)
        } }
        guard let loaded else { throw PipelineError.modelLoad }
        context = loaded
    }
    deinit { ov_free(context) }
    func synthesize(_ text: String, flag: SpeechCancelFlag) throws -> SpeechPCM {
        guard !flag.cancelled else { throw CancellationError() }
        var params = ov_tts_params(); ov_tts_default_params(&params)
        params.chunk_duration_sec = 5; params.chunk_threshold_sec = 5
        params.cancel = { data in wt_abort(data) }
        params.cancel_user_data = UnsafeMutableRawPointer(flag.pointer)
        var audio = ov_audio()
        defer { ov_audio_free(&audio) }
        let status = text.withCString { input in language.withCString { code in
            params.text = input; params.lang = code
            return ov_synthesize(context, &params, &audio)
        } }
        guard !flag.cancelled, status != OV_STATUS_CANCELLED else { throw CancellationError() }
        guard status == OV_STATUS_OK, audio.sample_rate == 24000, audio.channels == 1,
              audio.n_samples > 0, audio.n_samples <= 24000 * 60, let samples = audio.samples else { throw PipelineError.invalidAudio }
        let pcm = Array(UnsafeBufferPointer(start: samples, count: Int(audio.n_samples)))
        guard pcm.allSatisfy(\.isFinite), pcm.reduce(0.0, { $0 + Double($1) * Double($1) }) > 0.001 else { throw PipelineError.invalidAudio }
        return SpeechPCM(samples: pcm, sampleRate: Int(audio.sample_rate))
    }
}
private enum OmniVoiceError: LocalizedError {
    case memory
    var errorDescription: String? { L10n.text("Для OmniVoice сейчас недостаточно памяти. Выберите более лёгкий голос или закройте другие приложения.") }
}
