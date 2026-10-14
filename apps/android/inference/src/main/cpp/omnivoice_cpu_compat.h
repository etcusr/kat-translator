#pragma once
// Scope: only OmniVoice's private pinned ggml-cpu target. No advanced ARM ISA
// requirement, model conversion, or change to Index/Whisper's separate GGML.
#if defined(__aarch64__) && defined(__ARM_NEON) && !defined(__ARM_FEATURE_DOTPROD)
// Load the upstream internal header once, retaining its old helper only for
// the regression oracle. Later includes reuse its pragma-once definitions.
#define ggml_vdotq_s32 kat_omnivoice_original_vdotq_s32
#include "ggml-cpu-impl.h"
#undef ggml_vdotq_s32

// SDOT lane i contains products [4*i, 4*i+4), not two products from each
// vector half. Keeping only the total sum equal changes Q8 floating point
// accumulation and produces incorrect MaskGIT tokens with this pinned model.
static inline int32x4_t ggml_vdotq_s32(int32x4_t acc, int8x16_t a, int8x16_t b) {
    const int16x8_t lo = vmull_s8(vget_low_s8(a), vget_low_s8(b));
    const int16x8_t hi = vmull_s8(vget_high_s8(a), vget_high_s8(b));
    return vaddq_s32(acc, vpaddq_s32(vpaddlq_s16(lo), vpaddlq_s16(hi)));
}
#endif
