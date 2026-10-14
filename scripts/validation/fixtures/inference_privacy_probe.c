// Exercise real Kat entry points; replace only the external SDK boundary so the
// regression cannot initialize a real telemetry uploader or require model files.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "shared/native/app/Speech/SpeechRuntime.h"
#include "shared/native/app/Speech/WayuSpeechRuntime.h"
#include "shared/native/app/Camera/OCRRuntime.h"
#include <onnxruntime/onnxruntime_c_api.h>
static int calls;
static void entered_sdk(void) {
    const char *value = getenv("ORT_DISABLE_TELEMETRY");
    if (!value || strcmp(value, "1")) {
        fprintf(stderr, "SDK entered before process telemetry was disabled\n");
        exit(20);
    }
    calls++;
}
static const OrtApi *get_api(uint32_t version) { (void)version; entered_sdk(); return NULL; }
const OrtApiBase *OrtGetApiBase(void) { static const OrtApiBase api = {.GetApi = get_api}; return &api; }
const SherpaOnnxOfflineTts *SherpaOnnxCreateOfflineTts(const SherpaOnnxOfflineTtsConfig *c) {
    (void)c; entered_sdk(); return NULL;
}
const SherpaOnnxVoiceActivityDetector *SherpaOnnxCreateVoiceActivityDetector(const SherpaOnnxVadModelConfig *c, float seconds) {
    (void)c; (void)seconds; entered_sdk(); return NULL;
}
const SherpaOnnxOfflineRecognizer *SherpaOnnxCreateOfflineRecognizer(const SherpaOnnxOfflineRecognizerConfig *c) {
    (void)c; entered_sdk(); return NULL;
}
// Test-only failure injection used when compiling the privacy guard object.
int blocked_setenv(const char *name, const char *value, int overwrite) {
    (void)name; (void)value; (void)overwrite; return -1;
}
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    for (int repeat = 0; repeat < 2; repeat++) {
        switch (atoi(argv[1])) {
            case 0: ot_ocr_load("absent.onnx"); break;
            case 1: ot_wayu_load("a", "b", "c"); break;
            case 2: ot_tts_create("a", "b", "c"); break;
            case 3: ot_supertonic_create("absent"); break;
            case 4: ot_vad_create("absent.onnx"); break;
            case 5: ot_omni_create("a", "b"); break;
            default: return 2;
        }
    }
    if (calls != atoi(argv[2])) { fprintf(stderr, "Unexpected SDK call count: %d\n", calls); return 21; }
    return 0;
}
