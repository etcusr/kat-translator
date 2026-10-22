#!/usr/bin/env python3
"""Mac Index 9B runtime comparison on the frozen 30-case quantization corpus.

Engines: `gguf` = native llama.cpp/Metal TranslationRuntime (MTP2 if the library was built
with the iPhone KAT_IOS_MTP path), `mlx` = the production Mac MLX+MTP2 `index_mlx.Engine`.
Isolated: no Kat launch, no history/preferences/model writes. One process per run, greedy,
same prompt/suffix as the app, two warmup requests excluded, measured passes shuffled with the
same seeds as the quantization study. JSONL is append-flushed; existing outputs are never
overwritten. Thermal guard pauses at serious/critical state (wait excluded from timings).
"""
import argparse, ctypes as c, hashlib, json, os, random, subprocess, sys, threading, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
SUFFIX = '<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n'

def prefix(target):
    return '<|im_start|>user\n请将以下文本翻译为' + {'en': '英语', 'ru': '俄语'}[target] + '，直接输出翻译结果，不要进行任何解释。\n\n'

class Gguf:
    def __init__(self, library, model):
        L = self.lib = c.CDLL(str(library))
        L.ot_mt_load.argtypes = [c.c_char_p]; L.ot_mt_load.restype = c.c_void_p
        L.ot_mt_free.argtypes = [c.c_void_p]
        L.ot_mt_flag_create.restype = c.c_void_p; L.ot_mt_flag_free.argtypes = [c.c_void_p]
        L.ot_mt_count.argtypes = [c.c_void_p, c.c_char_p, c.c_char_p, c.c_char_p]; L.ot_mt_count.restype = c.c_int
        L.ot_mt_run.argtypes = [c.c_void_p, c.c_char_p, c.c_char_p, c.c_char_p, c.c_void_p, c.c_char_p, c.c_size_t, c.POINTER(c.c_double)]
        L.ot_mt_run.restype = c.c_int
        self.h = L.ot_mt_load(str(model).encode())
        if not self.h: raise RuntimeError('GGUF load failed')
    def run(self, p, text):
        parts = (p.encode(), text.encode(), SUFFIX.encode())
        n = self.lib.ot_mt_count(self.h, *parts)
        flag = self.lib.ot_mt_flag_create(); out = c.create_string_buffer(65536); first = c.c_double(-1)
        t = time.perf_counter()
        try: code = self.lib.ot_mt_run(self.h, *parts, flag, out, len(out), c.byref(first))
        finally: self.lib.ot_mt_flag_free(flag)
        return dict(code=code, output=out.value.decode('utf-8', 'replace').strip(), seconds=time.perf_counter() - t,
                    first_token_seconds=first.value, prompt_tokens=n)
    def close(self): self.lib.ot_mt_free(self.h)

class Mlx:
    def __init__(self, model):
        sys.path.insert(0, str(ROOT / '.build/mac-index-mlx-mtp/omlx'))
        sys.path.insert(0, str(ROOT / 'shared/native/IndexMLX'))
        from index_mlx import Engine
        self.e = Engine(str(model))
    def run(self, p, text):
        n = self.e.count(p, text, SUFFIX); t = time.perf_counter()
        code, out, first = self.e.run(p, text, SUFFIX, lambda: False)
        return dict(code=code, output=out, seconds=time.perf_counter() - t, first_token_seconds=first, prompt_tokens=n)
    def close(self): self.e.close()

def main():
    a = argparse.ArgumentParser()
    a.add_argument('--engine', choices=['gguf', 'mlx'], required=True)
    a.add_argument('--label', required=True); a.add_argument('--output', type=Path, required=True)
    a.add_argument('--model', type=Path, required=True); a.add_argument('--library', type=Path)
    a.add_argument('--metrics', type=Path, required=True)
    a.add_argument('--corpus', type=Path, default=ROOT / 'scripts/research/index-quantization/corpus.json')
    a.add_argument('--repeats', type=int, default=2)
    a = a.parse_args()
    cases = json.loads(a.corpus.read_text())['cases']
    m = c.CDLL(str(a.metrics)); m.kat_metrics.argtypes = [c.POINTER(c.c_double)]; m.kat_metrics.restype = c.c_int
    def metrics():
        v = (c.c_double * 5)(); assert m.kat_metrics(v) == 0
        return dict(zip(['footprint', 'resident', 'resident_process_peak', 'thermal', 'metal_allocated'], map(int, v)))
    swap = lambda: subprocess.check_output(['sysctl', 'vm.swapusage'], text=True).strip()
    a.output.parent.mkdir(parents=True, exist_ok=True)
    with a.output.open('x') as f:
        save = lambda d: (f.write(json.dumps(d, ensure_ascii=False) + '\n'), f.flush())
        files = sorted(p for p in a.model.rglob('*') if p.is_file()) if a.model.is_dir() else [a.model]
        save(dict(type='metadata', engine=a.engine, label=a.label, model=str(a.model), model_bytes=sum(p.stat().st_size for p in files),
                  library=str(a.library) if a.library else None, corpus_cases=len(cases), repeats=a.repeats, started=time.time(),
                  python=sys.version, swap=swap(), metrics=metrics(),
                  env={k: os.environ.get(k) for k in ['GGML_METAL_NO_RESIDENCY']}))
        t = time.perf_counter()
        engine = Gguf(a.library, a.model) if a.engine == 'gguf' else Mlx(a.model)
        save(dict(type='loaded', seconds=time.perf_counter() - t, metrics=metrics(), swap=swap()))
        try:
            warm = [dict(id='warm-ru-en', text='Спасибо за помощь. До встречи завтра.', target='en'),
                    dict(id='warm-en-ru', text='Thank you for your help. See you tomorrow.', target='ru')]
            for rep in range(a.repeats + 1):
                order = warm if rep == 0 else list(cases)
                if rep: random.Random(2100 + rep).shuffle(order)
                for item in order:
                    waited = 0
                    while metrics()['thermal'] >= 2 and waited < 600: time.sleep(5); waited += 5
                    if metrics()['thermal'] >= 2: raise RuntimeError('thermal guard: serious after 10 min')
                    samples = [metrics()]; stop = threading.Event()
                    def sample():
                        while not stop.wait(.1): samples.append(metrics())
                    th = threading.Thread(target=sample, daemon=True); th.start()
                    try: r = engine.run(prefix(item['target']), item['text'])
                    finally: stop.set(); th.join(); samples.append(metrics())
                    r.update(type='result', id=item['id'], pass_number=rep, warmup=rep == 0, thermal_wait_seconds=waited,
                             memory_peak={k: max(s[k] for s in samples) for k in samples[0]})
                    save(r); print(a.label, rep, item['id'], round(r['seconds'], 3), r['code'], flush=True)
                    if r['code'] != 0: raise RuntimeError('decode failed: %s' % r['code'])
        finally:
            engine.close()
        save(dict(type='completed', finished=time.time(), metrics=metrics(), swap=swap()))

if __name__ == '__main__':
    main()
