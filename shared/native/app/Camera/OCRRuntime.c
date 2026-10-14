#include "../Privacy/InferencePrivacy.h"
#include "OCRRuntime.h"
#include <onnxruntime/onnxruntime_c_api.h>
#include <stdlib.h>
#include <math.h>
typedef struct { const OrtApi *api; OrtEnv *env; OrtSession *session; OrtMemoryInfo *memory; OrtAllocator *allocator; char *input; char *output; int height; } OCR;
static int ok(OCR *c, OrtStatus *s) { if (!s) return 1; c->api->ReleaseStatus(s); return 0; }
void ot_ocr_free(void *handle) {
    OCR *c = handle; if (!c) return;
    if (c->input) c->allocator->Free(c->allocator, c->input);
    if (c->output) c->allocator->Free(c->allocator, c->output);
    if (c->memory) c->api->ReleaseMemoryInfo(c->memory);
    if (c->session) c->api->ReleaseSession(c->session);
    if (c->env) c->api->ReleaseEnv(c->env); free(c);
}
void *ot_ocr_load(const char *path) {
    if (!ot_prepare_inference_privacy()) return NULL;
    OCR *c = calloc(1, sizeof(OCR)); if (!c) return NULL;
    c->api = OrtGetApiBase()->GetApi(17); if (!c->api) { free(c); return NULL; }
    OrtSessionOptions *options = NULL; OrtTypeInfo *type = NULL;
    if (!ok(c,c->api->CreateEnv(ORT_LOGGING_LEVEL_FATAL,"offline-ocr",&c->env)) ||
        !ok(c,c->api->DisableTelemetryEvents(c->env)) ||
        !ok(c,c->api->CreateSessionOptions(&options))) goto fail;
    if (!ok(c,c->api->SetIntraOpNumThreads(options,2)) || !ok(c,c->api->DisableCpuMemArena(options)) ||
        !ok(c,c->api->CreateSession(c->env,path,options,&c->session))) goto fail;
    c->api->ReleaseSessionOptions(options); options = NULL;
    if (!ok(c,c->api->GetAllocatorWithDefaultOptions(&c->allocator)) ||
        !ok(c,c->api->SessionGetInputName(c->session,0,c->allocator,&c->input)) ||
        !ok(c,c->api->SessionGetOutputName(c->session,0,c->allocator,&c->output)) ||
        !ok(c,c->api->CreateCpuMemoryInfo(OrtArenaAllocator,OrtMemTypeDefault,&c->memory)) ||
        !ok(c,c->api->SessionGetInputTypeInfo(c->session,0,&type))) goto fail;
    const OrtTensorTypeAndShapeInfo *shape = NULL; int64_t dims[4]; size_t count = 0;
    if (!ok(c,c->api->CastTypeInfoToTensorInfo(type,&shape)) || !ok(c,c->api->GetDimensionsCount(shape,&count)) || count != 4 ||
        !ok(c,c->api->GetDimensions(shape,dims,4))) goto fail;
    c->height = dims[2] > 0 ? (int)dims[2] : 48;
    c->api->ReleaseTypeInfo(type); type = NULL;
    if (c->height < 16 || c->height > 96) goto fail;
    return c;
fail:
    if (type) c->api->ReleaseTypeInfo(type);
    if (options) c->api->ReleaseSessionOptions(options);
    ot_ocr_free(c); return NULL;
}
int ot_ocr_height(void *handle) { return handle ? ((OCR *)handle)->height : 0; }
int ot_ocr_run(void *handle, const float *input, int width, int *ids, int capacity) {
    OCR *c = handle; if (!c || !input || !ids || width < 8 || width > 4096 || capacity < 1) return -1;
    int64_t dims[4] = {1,3,c->height,width}; OrtValue *in = NULL, *out = NULL; OrtTensorTypeAndShapeInfo *shape = NULL; int result = -1;
    size_t bytes = (size_t)3*c->height*width*sizeof(float);
    if (!ok(c,c->api->CreateTensorWithDataAsOrtValue(c->memory,(void *)input,bytes,dims,4,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,&in))) goto end;
    const OrtValue *inputs[] = {in}; const char *names[] = {c->input}, *outputs[] = {c->output};
    if (!ok(c,c->api->Run(c->session,NULL,names,inputs,1,outputs,1,&out)) || !ok(c,c->api->GetTensorTypeAndShape(out,&shape))) goto end;
    size_t rank = 0; int64_t sizes[3]; ONNXTensorElementDataType dtype;
    if (!ok(c,c->api->GetDimensionsCount(shape,&rank)) || rank != 3 || !ok(c,c->api->GetDimensions(shape,sizes,3)) ||
        !ok(c,c->api->GetTensorElementType(shape,&dtype)) || dtype != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
        sizes[0] != 1 || sizes[1] < 1 || sizes[1] > capacity || sizes[2] < 2 || sizes[2] > 30000) goto end;
    float *values = NULL; if (!ok(c,c->api->GetTensorMutableData(out,(void **)&values))) goto end;
    for (int t=0; t<sizes[1]; ++t) {
        int best = 0; float score = -INFINITY;
        for (int j=0; j<sizes[2]; ++j) { float value = values[t*sizes[2]+j]; if (!isfinite(value)) goto end; if (value > score) { score=value; best=j; } }
        ids[t]=best;
    }
    result = (int)sizes[1];
end:
    if (shape) c->api->ReleaseTensorTypeAndShapeInfo(shape);
    if (out) c->api->ReleaseValue(out);
    if (in) c->api->ReleaseValue(in);
    return result;
}
