#!/usr/bin/env python3
"""Launch the packaged Mac app as a child and verify normal Dock-style Quit.
Uses opt-in metadata-only MT tracing; records no translated text or microphone audio.
"""
import argparse, json, os, subprocess, time
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("app", type=Path)
p.add_argument("helper", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
report = []

def phases(path):
    rows = []
    if path.exists():
        for line in path.read_text().splitlines():
            try: rows.append(json.loads(line))
            except json.JSONDecodeError: pass
    return rows

for name, trigger in [("cold", None), ("loaded-index", "load.complete"), ("loading-index", "load.start")]:
    trace = (a.output / (name + ".jsonl")).resolve()
    assert not trace.exists(), "Use a fresh output directory for each run"
    env = dict(os.environ, OT_MT_MEMORY_TRACE="1", OT_MT_MEMORY_TRACE_PATH=str(trace))
    args = [str(a.app.resolve() / "Contents/MacOS/Kat translator"),
            "-languageSetupCompleted", "YES", "-automaticModelLoad", "YES" if trigger else "NO",
            "-selectedTranslationModel", "index-translate-9b-q4km", "-memorySaving", "NO"]
    with (a.output / (name + ".log")).open("w") as log:
        proc = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 60
            if trigger:
                while not any(r["phase"] == trigger for r in phases(trace)):
                    assert proc.poll() is None, f"{name}: app exited before preparation"
                    assert time.monotonic() < deadline, f"{name}: preparation timed out"
                    time.sleep(0.01)
            else:
                time.sleep(2)
            requested = time.time()
            subprocess.run([str(a.helper.resolve()), str(proc.pid)], check=True)
            code = proc.wait(timeout=30)
            rows = phases(trace)
            summary = {"scenario": name, "pid": proc.pid, "exitCode": code,
                       "quitSeconds": round(time.time() - requested, 3),
                       "phases": [r["phase"] for r in rows],
                       "requestedBeforeLoadCompleted": not any(r["phase"] == "load.complete" and r["timestamp"] <= requested for r in rows)}
            report.append(summary)
            (a.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps(summary), flush=True)
            assert code == 0, f"{name}: normal Quit must not abort or receive a signal"
            if trigger:
                assert rows[-1]["phase"] == "unload.complete", f"{name}: Index must unload before exiting"
            if name == "loading-index":
                assert summary["requestedBeforeLoadCompleted"], "Quit must actually occur during model loading"
        finally:
            if proc.poll() is None:
                subprocess.run([str(a.helper.resolve()), str(proc.pid)], check=False)
                try: proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.terminate(); proc.wait(timeout=10)
