#!/usr/bin/env python3
"""Generate diagnostic-only Android translation units; never modify shared vendor."""
from pathlib import Path
import sys

source, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
# The compatibility shim replaces this one pinned fallback. Fail closed if the
# vendor implementation changes so it can be reviewed rather than double-fixed.
fallback = (source.parent / 'ggml/src/ggml-cpu/ggml-cpu-impl.h').read_text()
assert fallback.count('return vaddq_s32(acc, vaddq_s32(vpaddlq_s16(p0), vpaddlq_s16(p1)));') == 1, 'OmniVoice SDOT fallback changed' 

def replace(text, before, after):
    if text.count(before) != 1:
        raise SystemExit(f"Pinned OmniVoice diagnostic anchor changed: {before[:100]}")
    return text.replace(before, after)

pipeline = (source / 'pipeline-tts.cpp').read_text()
pipeline = replace(pipeline, '''    if (tokens.empty()) {
        return {};
    }''', '''    if (tokens.empty()) {
        ov_log(OV_LOG_ERROR, "[Android-TTS] MaskGIT returned zero tokens");
        return {};
    }''')
pipeline = replace(pipeline, '''    size_t before = audio.size();''', '''    size_t before = audio.size();
    // Counts and aggregate energy only. Never record the prompt or PCM values.
    size_t nonfinite = 0;
    double energy = 0.0, peak = 0.0;
    for (float sample : audio) {
        if (!std::isfinite(sample)) { ++nonfinite; continue; }
        energy += double(sample) * double(sample);
        peak = std::max(peak, std::abs(double(sample)));
    }
    ov_log(OV_LOG_INFO, "[Android-TTS] Before postproc: samples=%zu nonfinite=%zu energy=%.9g peak=%.9g",
           audio.size(), nonfinite, energy, peak);''')
(output / 'pipeline-tts.cpp').write_text(pipeline)
maskgit = (source / 'maskgit-tts.h').read_text()
maskgit = replace(maskgit, '''        fprintf(stderr, "[MaskGIT] FATAL: T=%d exceeds S=%d\\n", T, S);''', '''        ov_log(OV_LOG_ERROR, "[MaskGIT] FATAL: T=%d exceeds S=%d", T, S);''')
maskgit = replace(maskgit, '''        return {};
    }
    if (T > S)''', '''        ov_log(OV_LOG_ERROR, "[MaskGIT] invalid dimensions T=%d K=%d S=%d", T, K, S);
        return {};
    }
    if (T > S)''')
maskgit = replace(maskgit, '''            fprintf(stderr, "[MaskGIT] FATAL: forward returned %zu f32 (expected %zu)\\n", logits_full.size(), expected);''', '''            ov_log(OV_LOG_ERROR, "[MaskGIT] FATAL step=%d: forward returned %zu f32 (expected %zu)", step, logits_full.size(), expected);''')
# A numeric check identifies NaN propagation before sampler/postprocessing hides it.
maskgit = replace(maskgit, '''        // Extract cond and uncond logits at audio positions, layout [K, T, V].''', '''        if (step == 0) {
            size_t nonfinite = 0;
            for (float value : logits_full) if (!std::isfinite(value)) ++nonfinite;
            ov_log(OV_LOG_INFO, "[Android-TTS] First logits: count=%zu nonfinite=%zu", logits_full.size(), nonfinite);
        }
        // Extract cond and uncond logits at audio positions, layout [K, T, V].''')
(output / 'maskgit-tts.h').write_text(maskgit)
prompt = (source / 'prompt-tts.h').read_text()
prompt = replace(prompt, '''        fprintf(stderr, "[Prompt] FATAL: num_target_tokens must be positive (got %d)\\n", num_target_tokens);''', '''        ov_log(OV_LOG_ERROR, "[Prompt] FATAL: num_target_tokens must be positive (got %d)", num_target_tokens);''')
prompt = replace(prompt, '''        fprintf(stderr, "[Prompt] FATAL: ref_audio_tokens != NULL requires ref_T > 0 (got %d)\\n", ref_T);''', '''        ov_log(OV_LOG_ERROR, "[Prompt] FATAL: ref_audio_tokens != NULL requires ref_T > 0 (got %d)", ref_T);''')
(output / 'prompt-tts.h').write_text(prompt)

# Reference comparisons use compact statistics, never dump prompt or waveform.
pipeline = (output / 'pipeline-tts.cpp').read_text()
pipeline = replace(pipeline, '''    const int K       = pt->lm.num_audio_codebook;
    const int mask_id = pt->lm.audio_mask_id;''', '''    uint64_t token_hash = 1469598103934665603ULL;
    for (int32_t token : tokens) { token_hash ^= uint32_t(token); token_hash *= 1099511628211ULL; }
    ov_log(OV_LOG_INFO, "[Android-TTS] Tokens: count=%zu hash=%016llx", tokens.size(), (unsigned long long)token_hash);
    const int K       = pt->lm.num_audio_codebook;
    const int mask_id = pt->lm.audio_mask_id;''')
(output / 'pipeline-tts.cpp').write_text(pipeline)
codec = (source / 'pipeline-codec.cpp').read_text()
codec = replace(codec, '''    const bool dump = std::getenv("OMNIVOICE_DUMP_STAGES") != NULL;
    if (dump) {
        ggml_set_output(latent);''', '''    const bool dump = true; // Android numerical diagnosis: statistics only, no files.
    if (dump) {
        ggml_set_output(latent);''')
codec = replace(codec, '''            FILE * f = utf8_fopen(path, "wb");
            fwrite(tmp.data(), sizeof(float), n, f);
            fclose(f);
            ov_log(OV_LOG_INFO, "[PipelineCodec] Dumped %s: %zu f32 values, ne=(%lld, %lld, %lld, %lld)", path, n,
                   (long long) t->ne[0], (long long) t->ne[1], (long long) t->ne[2], (long long) t->ne[3]);''', '''            double energy = 0.0, peak = 0.0, sum = 0.0;
            size_t nonfinite = 0;
            for (float value : tmp) {
                if (!std::isfinite(value)) { ++nonfinite; continue; }
                sum += value; energy += double(value) * double(value);
                peak = std::max(peak, std::abs(double(value)));
            }
            ov_log(OV_LOG_INFO, "[Android-TTS] Codec %s: n=%zu nonfinite=%zu sum=%.9g energy=%.9g peak=%.9g",
                   path, n, nonfinite, sum, energy, peak);''')
(output / 'pipeline-codec.cpp').write_text(codec)
