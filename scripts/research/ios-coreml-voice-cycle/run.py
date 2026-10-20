"""Acoustic UI run against only the separately identified lab app."""
import argparse
import os
import subprocess
import time
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--device", required=True)
p.add_argument("--work", type=Path, required=True)
p.add_argument("--name", required=True)
p.add_argument("--short", type=Path, required=True)
p.add_argument("--long", type=Path, required=True)
p.add_argument("--baseline", action="store_true")
p.add_argument("--date-input", type=Path, action="append", default=[])
p.add_argument("--capture-output", action="store_true")
a = p.parse_args()
assert ".build" in a.work.resolve().parts
assert not (a.work / (a.name + ".xcresult")).exists()
project = a.work / "source/apps/ios/OfflineTranslator.xcodeproj"
assert "app.kattranslator.voicelab" in (project / "project.pbxproj").read_text()
assert not a.date_input or len(a.date_input) == 4
env = dict(os.environ, TEST_RUNNER_LAB_BASELINE=str(int(a.baseline)),
           TEST_RUNNER_LAB_DATES=str(int(bool(a.date_input))), TEST_RUNNER_LAB_ACOUSTIC="1", NSUnbufferedIO="YES")
cmd = ["xcodebuild", "test-without-building", "-project", str(project),
       "-scheme", "OfflineTranslator", "-configuration", "Release",
       "-destination", "platform=iOS,id=" + a.device,
       "-derivedDataPath", str(a.work / "Derived"),
       "-resultBundlePath", str(a.work / (a.name + ".xcresult")),
       "-only-testing:TranslatorUITests/TranslatorUITests/testVoiceLab"]
players, captures = [], []
started = time.monotonic()
with (a.work / (a.name + ".log")).open("w") as log:
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    try:
        for line in proc.stdout:
            log.write(line); log.flush()
            if "VOICE_LAB_" in line or "** TEST" in line or " error:" in line or " failed" in line:
                print(line.strip(), flush=True)
            if "VOICE_LAB_CAPTURE_READY_" in line:
                cycle = int(line.strip().split("VOICE_LAB_CAPTURE_READY_")[-1])
                stimulus = a.date_input[cycle] if a.date_input else (a.long if cycle == 3 else a.short)
                players.append(subprocess.Popen(["afplay", str(stimulus)]))
            if "VOICE_LAB_PLAYBACK_READY_" in line and a.capture_output:
                cycle = int(line.strip().split("VOICE_LAB_PLAYBACK_READY_")[-1])
                f = (a.work / f"{a.name}-speaker-{cycle}.log").open("w")
                c = subprocess.Popen(["ffmpeg", "-nostdin", "-hide_banner", "-y",
                                      "-f", "avfoundation", "-i", ":0", "-t", "50",
                                      "-ac", "1", "-ar", "16000",
                                      str(a.work / f"{a.name}-speaker-{cycle}.wav")],
                                     stdout=f, stderr=subprocess.STDOUT)
                captures.append((c, f))
            if "VOICE_LAB_CYCLE_FINISHED_" in line:
                for capture, _ in captures:
                    if capture.poll() is None:
                        capture.terminate(); capture.wait(timeout=10)
            if time.monotonic() - started > 1200:
                proc.terminate()
                raise TimeoutError("Acoustic UI run exceeded 20 minutes")
        code = proc.wait()
    finally:
        if proc.poll() is None:
            proc.terminate(); proc.wait(timeout=20)
        for player in players:
            if player.poll() is None:
                player.terminate(); player.wait(timeout=10)
        for capture, f in captures:
            if capture.poll() is None:
                capture.terminate(); capture.wait(timeout=10)
            f.close()
# Private traces stay outside Git. App teardown does not delete its container.
for name in ["voice-lab.jsonl", "tts-memory-probe.jsonl"]:
    with (a.work / (a.name + "-copy.log")).open("a") as log:
        subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", a.device,
                        "--domain-type", "appDataContainer", "--domain-identifier", "app.kattranslator.voicelab",
                        "--source", "Documents/" + name,
                        "--destination", str(a.work / (a.name + "-" + name))],
                       stdout=log, stderr=subprocess.STDOUT)
raise SystemExit(code)
