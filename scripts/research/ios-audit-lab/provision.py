"""Install Kat Audit Lab and seed only its own container. Never reads or writes Kat's container.

Copies Index 9B, Index 2B and the Irina/Lessac voices with receipts; normal model verification
stays on. Whisper Q8 is not copied: downloading it inside the lab is the O16 check."""
import argparse
import json
import subprocess
from pathlib import Path

BUNDLE = "app.kattranslator.voicelab"
p = argparse.ArgumentParser()
p.add_argument("--device", required=True)
p.add_argument("--work", type=Path, required=True)
p.add_argument("--model-store", type=Path, required=True, help="model-store directory of the primary checkout")
a = p.parse_args()
w = a.work.resolve()
assert ".build" in w.parts
app = w / "Derived/Build/Products/Release-iphoneos/OfflineTranslator.app"
actual = subprocess.check_output(["/usr/libexec/PlistBuddy", "-c", "Print CFBundleIdentifier", str(app / "Info.plist")], text=True).strip()
assert actual == BUNDLE, actual
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)

def apps():
    out = subprocess.check_output(["xcrun", "devicectl", "device", "info", "apps", "--device", a.device], text=True)
    return sorted(line.split()[0:5] for line in out.splitlines() if "app.kattranslator" in line)
before = apps()
assert not any(BUNDLE in " ".join(row) for row in before), "a lab copy is already installed; remove it first"

models_dir = "Library/Application Support/OfflineTranslator/Models"
seed = w / "seed"
(seed / models_dir).mkdir(parents=True, exist_ok=True)
catalog = json.loads((w / "source/assets/catalogs/models.json").read_text())
wanted = {"indexTranslation": a.model_store / "downloads/Index-Translate-9B.Q4_K_M.gguf",
          "indexTranslation2B": a.model_store / "research/index-2b/Index-Translate-2B.Q4_K_M.gguf",
          "lessacVoice": a.model_store / "downloads/vits-piper-en_US-lessac-medium.tar.bz2",
          "irinaVoice": a.model_store / "downloads/vits-piper-ru_RU-irina-medium.tar.bz2"}
files = []
for m in catalog["models"]:
    if m["symbol"] in wanted:
        source = wanted[m["symbol"]].resolve()
        assert source.stat().st_size == m["byteCount"], (source, m["byteCount"])
        (seed / models_dir / (m["id"] + ".json")).write_text(json.dumps({k: m[k] for k in ["id", "title", "remoteURL", "byteCount", "sha256"]}))
        files.append((source, models_dir + "/" + m["id"] + ".bin"))
assert len(files) == len(wanted)
common = ["--device", a.device, "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE]
with (w / "provision.log").open("w") as log:
    def run(*args):
        subprocess.run(["xcrun", "devicectl", *args], check=True, stdout=log, stderr=subprocess.STDOUT)
    run("device", "install", "app", "--device", a.device, str(app))
    run("device", "copy", "to", *common, "--source", str(seed), "--destination", ".")
    for source, dest in files:
        print("Copying", source.name, flush=True)
        run("device", "copy", "to", *common, "--source", str(source), "--destination", dest)
after = apps()
kat = lambda rows: [r for r in rows if BUNDLE not in " ".join(r)]
assert kat(before) == kat(after), "Kat changed during provisioning"
print("Kat Audit Lab installed and seeded; Kat unchanged:", kat(after), flush=True)
