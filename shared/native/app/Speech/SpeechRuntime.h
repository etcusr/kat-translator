#ifndef OT_SPEECH_RUNTIME_H
#define OT_SPEECH_RUNTIME_H
#include <sherpa-onnx/c-api/c-api.h>
#include "../ASR/WhisperCancellation.h"
const SherpaOnnxOfflineTts *ot_tts_create(const char *model, const char *tokens, const char *data);
const SherpaOnnxGeneratedAudio *ot_tts_generate(const SherpaOnnxOfflineTts *tts, const char *text, void *flag);
const SherpaOnnxOfflineTts *ot_supertonic_create(const char *directory);
const SherpaOnnxGeneratedAudio *ot_supertonic_generate(const SherpaOnnxOfflineTts *tts, const char *text, const char *language, void *flag);
const SherpaOnnxVoiceActivityDetector *ot_vad_create(const char *model);
const SherpaOnnxOfflineRecognizer *ot_omni_create(const char *model, const char *tokens);
#endif
