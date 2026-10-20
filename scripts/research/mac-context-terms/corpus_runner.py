#!/usr/bin/env python3
"""Frozen synthetic corpus evaluation; never tunes or falls back on failed cases."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from runner import Experiment, plan


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_request(experiment, case, mode):
    partials = []
    started = time.perf_counter()
    try:
        return dict(ok=True, **experiment.run(case, mode, partials.append))
    except Exception as error:
        return dict(ok=False, mode=mode, seconds=time.perf_counter()-started,
                    error=f"{type(error).__name__}: {error}", events=partials)


def parity(experiment, case, executable):
    with tempfile.TemporaryDirectory(prefix="kat-corpus-") as directory:
        fixture = Path(directory)/"fixture.json"
        fixture.write_text(json.dumps(case, ensure_ascii=False))
        child = subprocess.Popen([str(executable), str(fixture)], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, text=True)
        found = None
        try:
            for line in child.stdout:
                item = json.loads(line)
                if "count" in item:
                    child.stdin.write(str(experiment.count(item["count"]))+"\n")
                    child.stdin.flush()
                else:
                    expected = [plan(block, experiment.count) for block in case["blocks"]]
                    if item["pieces"] != expected:
                        raise AssertionError("Production Swift/Python boundaries differ")
                    found = dict(equal=True, pieces_per_block=list(map(len, expected)))
            if child.wait() != 0 or found is None:
                raise AssertionError("Swift planner failed")
            return found
        finally:
            if child.poll() is None:
                child.kill()
            child.wait()
            child.stdin.close()
            child.stdout.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=Path(__file__).with_name("corpus.json"))
    parser.add_argument("--frozen", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--swift-planner", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=2)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("At least one measured repeat required")
    frozen = json.loads(args.frozen.read_text())
    hashes = dict(corpus_sha256=sha(args.corpus),
                  fast_glossary_sha256=sha(Path(__file__).with_name("fast_glossary.py")))
    if frozen != hashes:
        raise ValueError("Frozen corpus/algorithm hash mismatch")
    cases = json.loads(args.corpus.read_text())["cases"]
    assert len({case["id"] for case in cases}) == len(cases)
    report = dict(frozen=hashes, results=[], planner_parity={}, complete=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        temporary = args.output.with_suffix(".pending")
        temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n")
        temporary.replace(args.output)

    experiment = Experiment()
    try:
        report["load_seconds"] = experiment.load_seconds
        for case in cases:
            report["planner_parity"][case["id"]] = parity(experiment, case, args.swift_planner)
        save()
        for repeat in range(args.repeats+1):
            ordered = cases[repeat:]+cases[:repeat]
            for case in ordered:
                modes = ["plain", "focused_terms"]
                if (repeat+cases.index(case)) % 2:
                    modes.reverse()
                for mode in modes:
                    row = run_request(experiment, case, mode)
                    row.update(case_id=case["id"], repeat=repeat,
                               phase="warmup" if repeat == 0 else "warm")
                    report["results"].append(row)
                    save()
                    print(f"{repeat} {case['id']} {mode} ok={row['ok']} "
                          f"total={row['seconds']:.3f} prep={row.get('glossary_seconds',0):.3f} "
                          f"{row.get('error','')}", file=sys.stderr, flush=True)
        report["frozen_unchanged"] = hashes == dict(
            corpus_sha256=sha(args.corpus),
            fast_glossary_sha256=sha(Path(__file__).with_name("fast_glossary.py")))
        report["complete"] = True
        save()
    finally:
        experiment.engine.close()


if __name__ == "__main__":
    main()
