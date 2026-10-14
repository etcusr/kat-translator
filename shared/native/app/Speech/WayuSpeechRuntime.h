#pragma once
#include <stdint.h>
void *ot_wayu_load(const char *prosody, const char *curves, const char *decoder);
void ot_wayu_free(void *handle);
float *ot_wayu_generate(void *handle, const int64_t *tokens, int count, const float *style, int *sample_count, void *flag);
void ot_wayu_audio_free(float *samples);
// Host excitation, also exposed for reference parity tests. Output: [1,22,samples/5+1].
float *ot_wayu_harmonic(const float *f0, int frames, int noise_enabled);
