// Isolated file-fed streaming ASR experiment; never reads app recordings/models.
#include "sherpa-onnx/c-api/c-api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

int streaming_probe(const char *model, const char *pcm, const char *output, int realtime, int beam) {
    char encoder[4096], decoder[4096], joiner[4096], tokens[4096];
    if (strlen(model) > 4000) return 1;
    snprintf(encoder, sizeof encoder, "%s/am-onnx/encoder.int8.onnx", model);
    snprintf(decoder, sizeof decoder, "%s/am-onnx/decoder.int8.onnx", model);
    snprintf(joiner, sizeof joiner, "%s/am-onnx/joiner.int8.onnx", model);
    snprintf(tokens, sizeof tokens, "%s/lang/tokens.txt", model);
    FILE *input = fopen(pcm, "rb"); if (!input) return 2;
    fseek(input, 0, SEEK_END); long bytes = ftell(input); rewind(input);
    if (bytes <= 0 || bytes % 4 || bytes > 16000L * 4 * 3600) { fclose(input); return 3; }
    float *audio = malloc(bytes); if (!audio) { fclose(input); return 4; }
    if (fread(audio, 1, bytes, input) != (size_t)bytes) { free(audio); fclose(input); return 5; }
    fclose(input);
    FILE *out = fopen(output, "w"); if (!out) { free(audio); return 6; }
    SherpaOnnxOnlineRecognizerConfig c = {0};
    c.feat_config.sample_rate = 16000; c.feat_config.feature_dim = 80;
    c.model_config.transducer.encoder = encoder;
    c.model_config.transducer.decoder = decoder;
    c.model_config.transducer.joiner = joiner;
    c.model_config.tokens = tokens; c.model_config.num_threads = 4;
    c.model_config.provider = "cpu";
    c.decoding_method = beam ? "modified_beam_search" : "greedy_search";
    c.max_active_paths = 10;
    // Keep one stateful stream. No arbitrary phrase cuts, endpoint reset or final re-recognition.
    double load = now();
    const SherpaOnnxOnlineRecognizer *r = SherpaOnnxCreateOnlineRecognizer(&c);
    if (!r) { fclose(out); free(audio); return 7; }
    fprintf(out, "{\"loadSeconds\":%.6f,\"realtime\":%d,\"beam\":%d}\n", now()-load, realtime, beam);
    const SherpaOnnxOnlineStream *s = SherpaOnnxCreateOnlineStream(r);
    if (!s) { SherpaOnnxDestroyOnlineRecognizer(r); fclose(out); free(audio); return 8; }
    double start = now(), compute = 0; long count = bytes / 4;
    char *previous = strdup("");
    for (long cursor = 0; cursor < count; cursor += 2560) {
        int n = (int)((count-cursor < 2560) ? count-cursor : 2560);
        if (realtime) {
            double delay = start + (cursor+n)/16000.0 - now();
            if (delay > 0) usleep((useconds_t)(delay*1e6));
        }
        double tick = now();
        SherpaOnnxOnlineStreamAcceptWaveform(s, 16000, audio+cursor, n);
        while (SherpaOnnxIsOnlineStreamReady(r,s)) SherpaOnnxDecodeOnlineStream(r,s);
        compute += now()-tick;
        const SherpaOnnxOnlineRecognizerResult *v = SherpaOnnxGetOnlineStreamResult(r,s);
        if (v && strcmp(previous,v->text)) {
            fprintf(out,"{\"audioSeconds\":%.6f,\"wallSeconds\":%.6f,\"result\":%s}\n",(cursor+n)/16000.0,now()-start,v->json);
            fflush(out); free(previous); previous=strdup(v->text);
        }
        if (v) SherpaOnnxDestroyOnlineRecognizerResult(v);
    }
    double stopped = now(), tick = now(); float padding[9600] = {0};
    SherpaOnnxOnlineStreamAcceptWaveform(s,16000,padding,9600);
    SherpaOnnxOnlineStreamInputFinished(s);
    while (SherpaOnnxIsOnlineStreamReady(r,s)) SherpaOnnxDecodeOnlineStream(r,s);
    compute += now()-tick;
    const SherpaOnnxOnlineRecognizerResult *v = SherpaOnnxGetOnlineStreamResult(r,s);
    fprintf(out,"{\"final\":true,\"audioSeconds\":%.6f,\"wallSeconds\":%.6f,\"afterStopSeconds\":%.6f,\"computeSeconds\":%.6f,\"result\":%s}\n",count/16000.0,now()-start,now()-stopped,compute,v ? v->json : "null");
    if (v) SherpaOnnxDestroyOnlineRecognizerResult(v);
    free(previous); free(audio); fclose(out);
    SherpaOnnxDestroyOnlineStream(s); SherpaOnnxDestroyOnlineRecognizer(r);
    return 0;
}

#ifndef IOS_PROBE
int main(int argc, char **argv) {
    if (argc != 6) { fprintf(stderr,"model pcm output realtime beam\n"); return 1; }
    return streaming_probe(argv[1],argv[2],argv[3],atoi(argv[4]),atoi(argv[5]));
}
#endif
