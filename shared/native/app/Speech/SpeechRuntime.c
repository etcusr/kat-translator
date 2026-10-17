#include "../Privacy/InferencePrivacy.h"
#include "SpeechRuntime.h"
#include <string.h>
#include <stdio.h>
#include <limits.h>
#if defined(__ANDROID__)
#include <unistd.h>
#endif
const SherpaOnnxOfflineTts *ot_supertonic_create(const char *directory) {
    if (!ot_prepare_inference_privacy()) return NULL;
    const char *names[] = {"duration_predictor.int8.onnx", "text_encoder.int8.onnx", "vector_estimator.int8.onnx", "vocoder.int8.onnx", "tts.json", "unicode_indexer.bin", "voice.bin"};
    char paths[7][PATH_MAX];
    for (int i = 0; i < 7; i++) {
        int n = snprintf(paths[i], sizeof(paths[i]), "%s/%s", directory, names[i]);
        if (n < 0 || n >= sizeof(paths[i])) return NULL;
    }
    SherpaOnnxOfflineTtsConfig config = {0};
    config.model.supertonic.duration_predictor = paths[0];
    config.model.supertonic.text_encoder = paths[1];
    config.model.supertonic.vector_estimator = paths[2];
    config.model.supertonic.vocoder = paths[3];
    config.model.supertonic.tts_json = paths[4];
    config.model.supertonic.unicode_indexer = paths[5];
    config.model.supertonic.voice_style = paths[6];
    config.model.num_threads = 2; config.model.provider = "cpu";
    return SherpaOnnxCreateOfflineTts(&config);
}
static int32_t supertonic_generated(const float *samples, int32_t n, float progress, void *flag) {
    (void)samples; (void)n; (void)progress; return wt_abort(flag) ? 0 : 1;
}
const SherpaOnnxGeneratedAudio *ot_supertonic_generate(const SherpaOnnxOfflineTts *tts, const char *text, const char *language, void *flag) {
    if (wt_abort(flag)) return NULL;
    // Only known language codes enter the JSON configuration.
    const char *supported[] = {"en", "ko", "ja", "ar", "bg", "cs", "da", "de", "el", "es", "et", "fi", "fr", "hi", "hr", "hu", "id", "it", "lt", "lv", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "tr", "uk", "vi"};
    int found = 0;
    for (int i = 0; i < sizeof(supported) / sizeof(supported[0]); i++) if (strcmp(language, supported[i]) == 0) found = 1;
    if (!found) return NULL;
    char extra[32]; snprintf(extra, sizeof(extra), "{\"lang\":\"%s\"}", language);
    SherpaOnnxGenerationConfig config = {0};
    config.sid = 0; config.speed = 1; config.num_steps = 8; config.extra = extra;
    return SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &config, supertonic_generated, flag);
}
const SherpaOnnxOfflineTts *ot_tts_create(const char *model, const char *tokens, const char *data) {
    if (!ot_prepare_inference_privacy()) return NULL;
    SherpaOnnxOfflineTtsConfig config; memset(&config, 0, sizeof(config));
    config.model.vits.model = model; config.model.vits.tokens = tokens; config.model.vits.data_dir = data;
    config.model.vits.noise_scale = 0.667f; config.model.vits.noise_scale_w = 0.8f; config.model.vits.length_scale = 1;
    config.model.num_threads = 2;
#if defined(__ANDROID__)
    // Pixel profiling: four threads reduce VITS inference latency; six regress.
    // Keep the model, precision, noise, duration and phonemization unchanged.
    long processors = sysconf(_SC_NPROCESSORS_ONLN);
    config.model.num_threads = processors > 0 && processors < 4 ? (int32_t)processors : 4;
#endif
    config.model.provider = "cpu"; config.max_num_sentences = 1; config.silence_scale = 1;
    return SherpaOnnxCreateOfflineTts(&config);
}
static int32_t generated(const float *samples, int32_t n, void *flag) { (void)samples; (void)n; return wt_abort(flag) ? 0 : 1; }
const SherpaOnnxGeneratedAudio *ot_tts_generate(const SherpaOnnxOfflineTts *tts, const char *text, void *flag) {
    if (wt_abort(flag)) return NULL;
    return SherpaOnnxOfflineTtsGenerateWithCallbackWithArg(tts, text, 0, 1, generated, flag);
}
const SherpaOnnxVoiceActivityDetector *ot_vad_create(const char *model) {
    if (!ot_prepare_inference_privacy()) return NULL;
    SherpaOnnxVadModelConfig config; memset(&config, 0, sizeof(config));
    config.silero_vad.model = model; config.silero_vad.threshold = 0.5f;
    config.silero_vad.min_silence_duration = 0.032f; config.silero_vad.min_speech_duration = 0.064f;
    config.silero_vad.window_size = 512; config.silero_vad.max_speech_duration = 300;
    config.sample_rate = 16000; config.num_threads = 1; config.provider = "cpu";
    return SherpaOnnxCreateVoiceActivityDetector(&config, 31);
}

const SherpaOnnxOfflineRecognizer *ot_omni_create(const char *model, const char *tokens) {
    if (!ot_prepare_inference_privacy()) return NULL;
    SherpaOnnxOfflineRecognizerConfig config = {0};
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.omnilingual.model = model;
    config.model_config.tokens = tokens;
    config.model_config.num_threads = 2;
    config.model_config.provider = "cpu";
    config.decoding_method = "greedy_search";
    return SherpaOnnxCreateOfflineRecognizer(&config);
}
