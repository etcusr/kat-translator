#!/usr/bin/env python3
"""Isolated Kat inference; synthetic benchmarks or one stdin request, no history."""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
SUFFIX = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("engine", choices=["index2b", "index9b"])
    parser.add_argument("--fixtures", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--repeats", type=int, default=3)
    args = parser.parse_args()
    if bool(args.fixtures) != bool(args.output):
        parser.error("--fixtures and --output must be used together")
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    cases = json.loads(args.fixtures.read_text()) if args.fixtures else [json.load(sys.stdin)]
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    started = time.perf_counter()
    # Third-party initialization logs must not corrupt the JSON stdout protocol.
    with contextlib.redirect_stdout(sys.stderr):
        if args.engine == "index2b":
            sys.path.insert(0, str(ROOT / "scripts/research"))
            from context_translation_probe import Engine
            model = ROOT / "model-store/research/index-2b/Index-Translate-2B.Q4_K_M.gguf"
            engine = Engine(ROOT / "Dependencies/build/translation/macosx/TranslationRuntime.framework/TranslationRuntime", model)
        else:
            sys.path.insert(0, str(ROOT / ".build/mac-index-mlx-mtp/omlx"))
            sys.path.insert(0, str(ROOT / "shared/native/IndexMLX"))
            from index_mlx import Engine
            model = Path.home() / "Library/Application Support/OfflineTranslator/TranslationPackages/index-translate-9b-mlx-mtp2"
            engine = Engine(str(model))
    load_seconds = time.perf_counter() - started

    def run(case):
        target = {"ru": "俄语", "en": "英语"}[case["target"]]
        prefix = f"<|im_start|>user\n请将以下文本翻译为{target}，直接输出翻译结果，不要进行任何解释。\n\n"
        with contextlib.redirect_stdout(sys.stderr):
            if args.engine == "index2b":
                result = engine.run(prefix, case["text"])
            else:
                start = time.perf_counter()
                code, output, first = engine.run(prefix, case["text"], SUFFIX, lambda: False)
                result = dict(code=code, output=output, first_token_seconds=first, seconds=time.perf_counter()-start)
        return {**case, **result, "engine": args.engine, "load_seconds": load_seconds}

    try:
        if not args.fixtures:
            print(json.dumps(run(cases[0]), ensure_ascii=False))
        else:
            report = dict(engine=args.engine, load_seconds=load_seconds,
                          fixtures_sha256=hashlib.sha256(args.fixtures.read_bytes()).hexdigest(),
                          model=model.name, results=[])
            args.output.parent.mkdir(parents=True, exist_ok=True)
            # First full pass is explicitly excluded from warm summaries.
            for repeat in range(args.repeats + 1):
                for case in cases:
                    row = {**run(case), "pass": repeat, "phase": "first_pass" if repeat == 0 else "warm"}
                    report["results"].append(row)
                    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
                    print(f"{args.engine} {repeat} {case['id']} {row['seconds']:.3f}s code={row['code']}", file=sys.stderr, flush=True)
    finally:
        engine.close()


if __name__ == "__main__":
    main()
