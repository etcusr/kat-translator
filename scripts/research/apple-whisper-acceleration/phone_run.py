"""Run only the isolated probe and collect its private report; never touches Kat."""
import argparse
import json
import subprocess
import time
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--device", required=True)
p.add_argument("--work", type=Path, required=True)
p.add_argument("--run", required=True)
p.add_argument("--model", default="f16.bin")
p.add_argument("--mode", default="native", choices=["native", "mlx"])
p.add_argument("--timeout", type=int, default=600)
p.add_argument("--coreml-units", choices=["off", "all", "cpu-ne"], default="all")
p.add_argument("--shared-encoder", action="store_true")
p.add_argument("--cool", action="store_true")
p.add_argument("--mlx-fp16", action="store_true")
a = p.parse_args()
bundle = "app.kattranslator.whisper-research"
output = a.work / (a.run + ".json")
assert not output.exists(), "Use a fresh run name"
env = {"BENCH_MODEL": a.model, "BENCH_RUN": a.run, "BENCH_MODE": a.mode,
       "BENCH_COREML_UNITS": a.coreml_units, "BENCH_SHARED_ENCODER": str(int(a.shared_encoder)),
       "BENCH_COOL": str(int(a.cool)), "BENCH_MLX_FP16": str(int(a.mlx_fp16))}
with (a.work / (a.run + ".log")).open("w") as log:
    proc = subprocess.Popen([
        "xcrun", "devicectl", "device", "process", "launch",
        "--device", a.device, "--terminate-existing", "--console",
        "--environment-variables", json.dumps(env), bundle,
    ], stdout=log, stderr=subprocess.STDOUT)
    started = time.monotonic()
    previous = -1
    try:
        while time.monotonic() - started < a.timeout:
            time.sleep(10)
            copied = subprocess.run([
                "xcrun", "devicectl", "device", "copy", "from", "--device", a.device,
                "--domain-type", "appDataContainer", "--domain-identifier", bundle,
                "--source", "Documents/" + a.run + ".json", "--destination", str(output),
                "--timeout", "20",
            ], capture_output=True)
            if copied.returncode == 0:
                report = json.loads(output.read_text())
                count = len(report.get("rows", []))
                if count != previous:
                    print(a.run, count, "measurements", flush=True)
                    previous = count
                if report.get("error"):
                    raise RuntimeError(report["error"])
                if report.get("completed"):
                    print(a.run, "completed", flush=True)
                    break
            if proc.poll() is not None:
                raise RuntimeError(f"Probe exited before completion: {proc.returncode}")
        else:
            raise TimeoutError(f"Probe exceeded {a.timeout} seconds")
    finally:
        # devicectl forwards SIGTERM to this probe only, releasing its UI/resources.
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
