"""Install and seed only Kat Voice Lab. No reads/writes to the main app."""
import argparse
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--device", required=True)
p.add_argument("--work", type=Path, required=True)
p.add_argument("--model-store", type=Path, required=True)
p.add_argument("--whisper-models", type=Path, required=True)
a = p.parse_args()
w = a.work.resolve()
assert ".build" in w.parts
bundle = "app.kattranslator.voicelab"
app = w / "Derived/Build/Products/Release-iphoneos/OfflineTranslator.app"
actual = subprocess.check_output(["/usr/libexec/PlistBuddy", "-c", "Print CFBundleIdentifier",
                                  str(app / "Info.plist")], text=True).strip()
assert actual == bundle
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
seed = w / "seed"
models = seed / "Library/Application Support/OfflineTranslator/Models"
models.mkdir(parents=True, exist_ok=True)
(seed / "Documents/Research").mkdir(parents=True, exist_ok=True)
catalog = json.loads((w / "source/assets/catalogs/models.json").read_text())
for m in catalog["models"]:
    if m["symbol"] in {"turbo", "indexTranslation", "lessacVoice", "irinaVoice"}:
        receipt = {k: m[k] for k in ["id", "title", "remoteURL", "byteCount", "sha256"]}
        (models / (m["id"] + ".json")).write_text(json.dumps(receipt))
common = ["--device", a.device, "--domain-type", "appDataContainer", "--domain-identifier", bundle]
files = [
    (a.whisper_models / "turbo-q8_0.bin", "Library/Application Support/OfflineTranslator/Models/whisper-large-v3-turbo-q8-lab.bin"),
    (a.model_store / "Index-Translate-9B.Q4_K_M.gguf", "Library/Application Support/OfflineTranslator/Models/index-translate-9b-q4km.bin"),
    (a.model_store / "vits-piper-en_US-lessac-medium.tar.bz2", "Library/Application Support/OfflineTranslator/Models/vits-piper-en_US-lessac-medium.bin"),
    (a.model_store / "vits-piper-ru_RU-irina-medium.tar.bz2", "Library/Application Support/OfflineTranslator/Models/vits-piper-ru_RU-irina-medium.bin"),
    (a.whisper_models / "turbo-encoder.mlmodelc", "Documents/Research/turbo-encoder.mlmodelc"),
    (a.model_store / "whisper-large-v3-turbo-f16.bin", "Documents/Research/f16.bin"),
]
with (w / "provision.log").open("w") as log:
    def run(*args):
        subprocess.run(["xcrun", "devicectl", *args], check=True, stdout=log, stderr=subprocess.STDOUT)
    run("device", "install", "app", "--device", a.device, str(app))
    run("device", "copy", "to", *common, "--source", str(seed), "--destination", ".")
    for source, dest in files:
        print("Copying", source.name, flush=True)
        run("device", "copy", "to", *common, "--source", str(source.resolve()), "--destination", dest)
print("Independent lab installed and seeded", flush=True)
