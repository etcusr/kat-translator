"""Mac MLX comparison: loaded model, explicit language, greedy, no fallback/context."""
import argparse
import importlib
import json
import resource
import time
from pathlib import Path
import mlx.core as mx
import numpy as np
import mlx_whisper

p = argparse.ArgumentParser()
p.add_argument("model")
p.add_argument("manifest", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
items = json.loads(a.manifest.read_text())
report = {"backend": "mlx-whisper", "rows": []}
holder = importlib.import_module("mlx_whisper.transcribe").ModelHolder
start = time.perf_counter()
model = holder.get_model(a.model, mx.float16)
mx.eval(model.parameters())
mx.synchronize()
report["loadSeconds"] = time.perf_counter() - start
for repeat in range(4):
    for item in items if repeat % 2 == 0 else items[::-1]:
        audio = np.fromfile(a.manifest.parent / item["path"], dtype=np.float32)
        mx.synchronize()
        start = time.perf_counter()
        result = mlx_whisper.transcribe(
            audio, path_or_hf_repo=a.model, language=item["language"],
            task="transcribe", temperature=0.0, condition_on_previous_text=False,
            verbose=None, fp16=True, word_timestamps=False,
            compression_ratio_threshold=None, logprob_threshold=None,
        )
        mx.synchronize()
        elapsed = time.perf_counter() - start
        report["rows"].append({
            "id": item["id"], "pass": repeat, "warmup": repeat == 0,
            "seconds": elapsed, "audioSeconds": len(audio) / 16000,
            "text": result["text"], "peakRSS": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            "mlxPeak": mx.get_peak_memory(), "mlxActive": mx.get_active_memory(),
        })
        a.output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(item["id"], repeat, round(elapsed, 4), flush=True)
report["completed"] = True
a.output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
