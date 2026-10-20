#!/usr/bin/env python3
"""Profile unchanged MLX inference. No timers or in-process stack sampling."""
import argparse
import dataclasses
import gc
import json
from pathlib import Path
import resource
import sys
import time

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--passes", type=int, default=4)
    args = parser.parse_args()
    sys.path[:0] = [str(ROOT/".build/mac-index-mlx-mtp/omlx"),
                   str(ROOT/"shared/native/IndexMLX")]
    from index_mlx import Engine
    import mlx.core as mx
    from mlx_lm.generate import BatchGenerator
    from omlx.patches.mlx_lm_mtp import batch_generator as mtp
    from kat_runner import SUFFIX

    rows, events, telemetry = [], [], []
    original_log = mtp._log_mtp_stats

    def log_stats(uid, stats, reason):
        telemetry.append(dataclasses.asdict(stats))
        return original_log(uid, stats, reason)

    mtp._log_mtp_stats = log_stats
    for name in ("__init__", "next", "close"):
        original = getattr(BatchGenerator, name)

        def measured(self, *a, _name=name, _original=original, **kw):
            started, cpu = time.perf_counter(), time.process_time()
            try:
                return _original(self, *a, **kw)
            finally:
                events.append(dict(stage=_name, seconds=time.perf_counter()-started,
                                   cpu_seconds=time.process_time()-cpu))

        setattr(BatchGenerator, name, measured)
    gc_start = {}

    def gc_event(phase, info):
        generation = info["generation"]
        if phase == "start":
            gc_start[generation] = time.perf_counter()
        else:
            events.append(dict(stage=f"gc{generation}", collected=info["collected"],
                               seconds=time.perf_counter()-gc_start[generation]))

    def memory():
        usage = resource.getrusage(resource.RUSAGE_SELF)
        return dict(active=mx.get_active_memory(), cache=mx.get_cache_memory(),
                    peak=mx.get_peak_memory(), rss_peak=usage.ru_maxrss,
                    minflt=usage.ru_minflt, majflt=usage.ru_majflt,
                    nvcsw=usage.ru_nvcsw, nivcsw=usage.ru_nivcsw)

    gc.callbacks.append(gc_event)
    started = time.perf_counter()
    engine = Engine(str(Path.home()/"Library/Application Support/OfflineTranslator/TranslationPackages/index-translate-9b-mlx-mtp2"))
    load_seconds = time.perf_counter()-started
    cases = json.loads((ROOT/"tests/fixtures/mac-system-translation.json").read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        for repeat in range(args.passes):
            for case in cases:
                events.clear()
                telemetry.clear()
                before = memory()
                started, cpu = time.perf_counter(), time.process_time()
                target = {"ru": "俄语", "en": "英语"}[case["target"]]
                prefix = f"<|im_start|>user\n请将以下文本翻译为{target}，直接输出翻译结果，不要进行任何解释。\n\n"
                code, output, first = engine.run(prefix, case["text"], SUFFIX, lambda: False)
                row = dict(id=case["id"], repeat=repeat,
                           seconds=time.perf_counter()-started, cpu_seconds=time.process_time()-cpu,
                           first=first, code=code, output=output, before=before, after=memory(),
                           events=list(events), mtp=list(telemetry))
                rows.append(row)
                args.output.write_text(json.dumps(dict(load_seconds=load_seconds, rows=rows),
                                                 ensure_ascii=False, indent=2)+"\n")
                print(repeat, case["id"], f"{row['seconds']:.3f}s", flush=True)
    finally:
        engine.close()
        gc.callbacks.remove(gc_event)


if __name__ == "__main__":
    main()
