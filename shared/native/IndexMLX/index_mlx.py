"""Pinned offline Index runtime. Model downloads contain data only, never code."""
import gc
import os
import time
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'

class Engine:
    def __init__(self, path):
        import mlx.core as mx
        from mlx_lm import load
        from omlx.model_settings import ModelSettings
        from omlx.utils.model_loading import maybe_apply_pre_load_patches
        settings = ModelSettings(mtp_enabled=True, mtp_fixed_depth=2)
        maybe_apply_pre_load_patches(path, settings)
        from omlx.custom_kernels.qwen35_prefill import fast as prefill
        from omlx.custom_kernels.decode_fast import fast as decode
        if prefill._ext is None or decode._ext is None:
            raise RuntimeError('Packaged Index native kernels are unavailable')
        self.model, self.tokenizer = load(path)
        from omlx.patches.sdpa256_attention import apply_sdpa256_attention_patch
        from omlx.patches.qwen35_fa256_attention import apply_qwen35_fa256_attention_patch
        from omlx.patches.qwen35_q4_mlp import apply_qwen35_q4_mlp_patch, apply_qwen35_q4_lm_prefill_linear_patch
        for patch in [apply_sdpa256_attention_patch, apply_qwen35_fa256_attention_patch,
                      apply_qwen35_q4_mlp_patch, apply_qwen35_q4_lm_prefill_linear_patch]:
            patch()
        if getattr(self.model.language_model, 'mtp', None) is None or not getattr(self.model.language_model, '_omlx_mtp_decode_enabled', False):
            raise RuntimeError('Index MTP2 did not activate')
        self.mx = mx
        import sys
        print("Kat Index: MLX MTP2; native kernels active", file=sys.stderr, flush=True)

    def count(self, prefix, text, suffix):
        return len(self.tokenizer.encode(prefix + text + suffix, add_special_tokens=False))

    def run(self, prefix, text, suffix, cancelled):
        from mlx_lm.generate import BatchGenerator
        if cancelled(): return (2, '', -1.)
        start = time.perf_counter()
        tokens = self.tokenizer.encode(prefix + text + suffix, add_special_tokens=False)
        if not tokens or len(tokens) > 1536: return (1, '', -1.)
        gen = None
        try:
            gen = BatchGenerator(self.model, max_tokens=2048-len(tokens),
                stop_tokens=[[x] for x in self.tokenizer.eos_token_ids], completion_batch_size=1,
                prefill_batch_size=1, prefill_step_size=512)
            gen.insert([tokens])
            output = []; first = -1.; reason = None
            while reason is None:
                if cancelled(): return (2, '', -1.)
                _, responses = gen.next()
                for item in responses:
                    if first < 0: first = time.perf_counter()-start
                    if item.token not in self.tokenizer.eos_token_ids: output.append(item.token)
                    if item.finish_reason: reason = item.finish_reason
            self.mx.synchronize()
            if cancelled(): return (2, '', -1.)
            if reason != 'stop': return (1, '', -1.)
            translated = self.tokenizer.decode(output).strip()
            return (0, translated, first) if translated else (-1, '', -1.)
        finally:
            self.mx.synchronize()
            if gen is not None: gen.close()

    def close(self):
        self.mx.synchronize()
        self.model = None
        self.tokenizer = None
        gc.collect()
        self.mx.clear_cache()
