"""Physical iPhone file-input test. Never plays or records audio on the Mac."""
import argparse
import os
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--device", required=True)
p.add_argument("--work", type=Path, required=True)
p.add_argument("--variant", choices=["f16", "q8", "coreml-q8"], required=True)
p.add_argument("--name", required=True)
p.add_argument("--repeats", type=int, default=2)
p.add_argument("--speak", action="store_true", help="Opt in to iPhone TTS only for an explicitly requested playback check")
a = p.parse_args()
w = a.work.resolve()
assert ".build" in w.parts and 1 <= a.repeats <= 5
project = w / "source/apps/ios/OfflineTranslator.xcodeproj"
assert "app.kattranslator.voicelab" in (project / "project.pbxproj").read_text()
assert not (w / (a.name + ".xcresult")).exists()
env = dict(os.environ, TEST_RUNNER_LAB_VARIANT=a.variant, TEST_RUNNER_LAB_SPEAK=str(int(a.speak)),
           TEST_RUNNER_LAB_FILE_REPEATS=str(a.repeats), NSUnbufferedIO="YES")
cmd = ["xcodebuild", "test-without-building", "-project", str(project),
       "-scheme", "OfflineTranslator", "-configuration", "Release",
       "-destination", "platform=iOS,id=" + a.device,
       "-derivedDataPath", str(w / "Derived"),
       "-resultBundlePath", str(w / (a.name + ".xcresult")),
       "-only-testing:TranslatorUITests/TranslatorUITests/testFileImport"]
with (w / (a.name + ".log")).open("w") as log:
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    try:
        for line in proc.stdout:
            log.write(line); log.flush()
            if "VOICE_LAB_" in line or "** TEST" in line or " error:" in line:
                print(line.strip(), flush=True)
        code = proc.wait()
    finally:
        if proc.poll() is None:
            proc.terminate(); proc.wait(timeout=20)
with (w / (a.name + "-copy.log")).open("w") as log:
    for filename in ["voice-lab.jsonl", "tts-memory-probe.jsonl"]:
        subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", a.device,
                        "--domain-type", "appDataContainer", "--domain-identifier", "app.kattranslator.voicelab",
                        "--source", "Documents/" + filename, "--destination", str(w / (a.name + "-" + filename))],
                       check=True, stdout=log, stderr=subprocess.STDOUT)
raise SystemExit(code)
