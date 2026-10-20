// Experimental replacement for whisper.cpp's Core ML bridge (MIT licensed).
// Same encoder interface; exposes compute-unit selection without editing vendor sources.
#import <CoreML/CoreML.h>
#import "whisper-encoder-impl.h"
#include "whisper-encoder.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

struct whisper_coreml_context { const void *data; };

extern "C" whisper_coreml_context *whisper_coreml_init(const char *path) {
    MLModelConfiguration *config = [MLModelConfiguration new];
    const char *mode = getenv("BENCH_COREML_UNITS");
    if (mode && strcmp(mode, "off") == 0) return nullptr;
    const char *overridePath = getenv("BENCH_COREML_ENCODER");
    if (overridePath && overridePath[0]) path = overridePath;
    config.computeUnits = mode && strcmp(mode, "cpu-ne") == 0
        ? MLComputeUnitsCPUAndNeuralEngine : MLComputeUnitsAll;
    NSError *error = nil;
    id model = [[whisper_encoder_impl alloc]
        initWithContentsOfURL:[NSURL fileURLWithPath:@(path)]
        configuration:config error:&error];
    fprintf(stderr, "BENCH_COREML units=%s loaded=%d\n", mode ?: "all", model != nil);
    if (!model) return nullptr;
    return new whisper_coreml_context{CFBridgingRetain(model)};
}

extern "C" void whisper_coreml_free(whisper_coreml_context *ctx) {
    CFRelease(ctx->data);
    delete ctx;
}

extern "C" void whisper_coreml_encode(const whisper_coreml_context *ctx,
    int64_t n_ctx, int64_t n_mel, float *mel, float *out) {
    @autoreleasepool {
        MLMultiArray *input = [[MLMultiArray alloc] initWithDataPointer:mel
            shape:@[@1, @(n_mel), @(n_ctx)] dataType:MLMultiArrayDataTypeFloat32
            strides:@[@(n_ctx*n_mel), @(n_ctx), @1] deallocator:nil error:nil];
        NSError *error = nil;
        whisper_encoder_implOutput *result = [(__bridge id)ctx->data
            predictionFromLogmel_data:input error:&error];
        if (!result || result.output.dataType != MLMultiArrayDataTypeFloat32) {
            fprintf(stderr, "BENCH_COREML prediction failed: %s\n", error.description.UTF8String);
            abort();
        }
        memcpy(out, result.output.dataPointer, result.output.count * sizeof(float));
    }
}
