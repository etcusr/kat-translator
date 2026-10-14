#include "InferencePrivacy.h"
#include <pthread.h>
#include <stdlib.h>

static pthread_once_t once = PTHREAD_ONCE_INIT;
static int configured;
static void disable_telemetry(void) {
    // ONNX 1.30's API-level opt-out leaves ProcessInfo/uploader active.
    // Its process-wide flag is read on first Env initialization and latched.
    configured = setenv("ORT_DISABLE_TELEMETRY", "1", 1) == 0;
}
int ot_prepare_inference_privacy(void) {
    return pthread_once(&once, disable_telemetry) == 0 && configured;
}
