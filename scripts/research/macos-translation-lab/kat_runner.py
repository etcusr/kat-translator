#!/usr/bin/env python3
"""Isolated Kat inference; synthetic benchmarks or one stdin request, no history."""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import select
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
    parser.add_argument("--serve", action="store_true",
                        help="Serve newline-delimited requests with idle unloading")
    parser.add_argument("--idle-timeout", type=float, default=300,
                        help="Resident worker idle seconds (1–3600, default 300)")
    args = parser.parse_args()
    if bool(args.fixtures) != bool(args.output):
        parser.error("--fixtures and --output must be used together")
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    if args.serve and args.fixtures:
        parser.error("--serve cannot be combined with --fixtures")
    if not 1 <= args.idle_timeout <= 3600:
        parser.error("--idle-timeout must be between 1 and 3600 seconds")
    cases = json.loads(args.fixtures.read_text()) if args.fixtures else ([] if args.serve else [json.load(sys.stdin)])
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
        mode = case.get("mode", "whole")
        if mode not in ("whole", "chunk_plain", "chunk_context"):
            raise ValueError("Unknown translation mode")
        if mode != "whole" and args.engine != "index9b":
            raise ValueError("Chunk experiment requires Index 9B")
        target = {"ru": "俄语", "en": "英语"}[case["target"]]
        prefix = f"<|im_start|>user\n请将以下文本翻译为{target}，直接输出翻译结果，不要进行任何解释。\n\n"
        output_stream = sys.stdout
        def progress(event):
            print(json.dumps(event, ensure_ascii=False), file=output_stream, flush=True)
        with contextlib.redirect_stdout(sys.stderr):
            if mode != "whole":
                from chunking import translate
                result = translate(engine, case["text"], case["target"], SUFFIX, mode,
                                   progress if case.get("progress") is True else None)
                result["chunk_count"] = len(result["chunks"])
            elif args.engine == "index2b":
                result = engine.run(prefix, case["text"])
            else:
                start = time.perf_counter()
                code, output, first = engine.run(prefix, case["text"], SUFFIX, lambda: False)
                result = dict(code=code, output=output, first_token_seconds=first, seconds=time.perf_counter()-start)
        return {**case, **result, "engine": args.engine, "load_seconds": load_seconds}

    try:
        if args.serve:
            reused = False
            idle_timeout = args.idle_timeout
            while select.select([sys.stdin], [], [], idle_timeout)[0]:
                line = sys.stdin.readline()
                if not line:
                    break
                try:
                    case = json.loads(line)
                    if case.get("command") == "configure":
                        seconds = case.get("idle_timeout_seconds")
                        if isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or not 1 <= seconds <= 3600:
                            raise ValueError("Idle timeout must be between 1 and 3600 seconds")
                        idle_timeout = seconds
                        print(json.dumps({"idle_timeout_seconds": idle_timeout}), flush=True)
                        continue
                    if not isinstance(case.get("text"), str) or len(case["text"].encode()) > 12000:
                        raise ValueError("Expected text up to 12 KB")
                    if case.get("source") not in ("en", "ru") or case.get("target") not in ("en", "ru"):
                        raise ValueError("Expected RU/EN languages")
                    result = run(case)
                    result["model_reused"] = reused
                    result["load_seconds"] = 0 if reused else load_seconds
                    result["idle_timeout_seconds"] = idle_timeout
                    reused = True
                except (ValueError, KeyError, TypeError, AttributeError) as error:
                    result = {"error": str(error)}
                print(json.dumps(result, ensure_ascii=False), flush=True)
        elif not args.fixtures:
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
