"""Pinned offline Index runtime. Model downloads contain data only, never code."""
import gc
import os
import time
# Kat sets these before starting threads; setdefault avoids putenv() in its multithreaded process
# and still keeps research harnesses that import this module offline.
for _name in ('HF_HUB_OFFLINE', 'TRANSFORMERS_OFFLINE', 'HF_HUB_DISABLE_TELEMETRY'):
    os.environ.setdefault(_name, '1')


def _install_offline_ssl():
    """Store builds omit OpenSSL (_ssl). mlx_lm imports huggingface_hub/httpx, which
    import ssl at module level although local loading never opens a connection.
    Provide inert names for those imports; any real TLS use fails loudly."""
    try:
        import ssl  # noqa: F401
        return
    except ImportError:
        pass
    import sys
    import types

    class _Unavailable(type):
        def __getattr__(cls, name):
            if name.startswith('__'):
                raise AttributeError(name)
            return cls

    class _Inert(metaclass=_Unavailable):
        def __init__(self, *args, **kwargs):
            raise RuntimeError('TLS is not available in the offline Index runtime')

    def _missing(name):
        if name.startswith('__'):
            raise AttributeError(name)
        return _Inert

    module = types.ModuleType('ssl')
    module.__getattr__ = _missing
    module.HAS_SNI = module.HAS_ALPN = False
    module.OPENSSL_VERSION = ''
    sys.modules['ssl'] = module


_install_offline_ssl()

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

    def prepare_glossary(self, text, identity, cancelled):
        # Empty identity disables the experiment without importing morphology.
        if not identity:
            self._glossary = []; self._glossary_identity = None
            return 2 if cancelled() else 0
        if cancelled(): return 2
        if getattr(self, '_glossary_identity', None) == identity: return 0
        self._glossary = []; self._glossary_identity = None
        from index_glossary import build_fast_glossary, GlossaryCancelled
        try:
            result = build_fast_glossary(self, text.split('\n\n'), cancelled=cancelled)
            if cancelled(): return 2
            self._glossary = result['terms']
            self._glossary_identity = identity
            return 0
        except GlossaryCancelled:
            return 2
        # Invalid JSON/budget/dependency failures propagate; no silent plain fallback.

    def _prefix(self, prefix, text):
        terms = getattr(self, '_glossary', [])
        if not terms or not prefix: return prefix
        from index_glossary import translation_prefix
        return translation_prefix(prefix, text, terms)

    def count(self, prefix, text, suffix):
        return len(self.tokenizer.encode(self._prefix(prefix, text) + text + suffix, add_special_tokens=False))

    def run(self, prefix, text, suffix, cancelled, partial=None):
        from mlx_lm.generate import BatchGenerator
        if cancelled(): return (2, '', -1.)
        start = time.perf_counter()
        tokens = self.tokenizer.encode(self._prefix(prefix, text) + text + suffix, add_special_tokens=False)
        if not tokens or len(tokens) > 1536: return (1, '', -1.)
        gen = None
        try:
            gen = BatchGenerator(self.model, max_tokens=2048-len(tokens),
                stop_tokens=[[x] for x in self.tokenizer.eos_token_ids], completion_batch_size=1,
                prefill_batch_size=1, prefill_step_size=512)
            gen.insert([tokens])
            output = []; first = -1.; reason = None; last_partial = ''
            while reason is None:
                if cancelled(): return (2, '', -1.)
                _, responses = gen.next()
                for item in responses:
                    if first < 0: first = time.perf_counter()-start
                    if item.token not in self.tokenizer.eos_token_ids: output.append(item.token)
                    if item.finish_reason: reason = item.finish_reason
                if partial is not None and not cancelled():
                    # Decode the same accepted tokens as the final result. A token may
                    # end midway through a UTF-8 character; wait until it is complete.
                    current = self.tokenizer.decode(output).strip()
                    if current and not current.endswith('\ufffd') and current != last_partial:
                        partial(current)
                        last_partial = current
            self.mx.synchronize()
            if cancelled(): return (2, '', -1.)
            if reason != 'stop': return (1, '', -1.)
            translated = self.tokenizer.decode(output).strip()
            return (0, translated, first) if translated else (-1, '', -1.)
        finally:
            self.mx.synchronize()
            if gen is not None: gen.close()

    def close(self):
        self._glossary = []; self._glossary_identity = None
        self.mx.synchronize()
        self.model = None
        self.tokenizer = None
        gc.collect()
        self.mx.clear_cache()
