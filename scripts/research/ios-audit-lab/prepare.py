"""Build Kat Audit Lab: a committed Kat snapshot with its own bundle and data container.

It never replaces Kat or writes into Kat's container. The bundle ID reuses the existing
app.kattranslator.voicelab development profile, and the Live Activity extension is left out,
so no new App ID is registered in the developer account."""
import argparse
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--work", type=Path, required=True)
p.add_argument("--commit", default="HEAD")
a = p.parse_args()
repo = Path(__file__).resolve().parents[3]
w = a.work.resolve()
assert ".build" in w.parts and not (w / "source").exists(), "use a new directory under .build"
commit = subprocess.check_output(["git", "-C", str(repo), "rev-parse", a.commit], text=True).strip()
src = w / "source"
src.mkdir(parents=True)
# Committed files only: uncommitted work in the primary checkout is excluded.
archive = subprocess.run(["git", "-C", str(repo), "archive", commit, "apps", "shared", "assets", "scripts",
                          "docs", "tests", "PROJECT_DESCRIPTION.md"], capture_output=True, check=True).stdout
subprocess.run(["tar", "-x", "-C", str(src)], input=archive, check=True)
(src / "Dependencies").symlink_to(repo / "Dependencies")  # build outputs, read only in practice
shutil.copy2(repo / "apps/ios/Config/Signing.local.xcconfig", src / "apps/ios/Config/Signing.local.xcconfig")
(w / "commit.txt").write_text(commit + "\n")

info = src / "apps/ios/Info.plist"
d = plistlib.loads(info.read_bytes())
d["CFBundleDisplayName"] = "Kat Audit Lab"
d["CFBundleURLTypes"] = []
info.write_bytes(plistlib.dumps(d))
generator = src / "scripts/generate-project.py"
s = generator.read_text()
def replace(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)
replace("'PRODUCT_BUNDLE_IDENTIFIER':'app.kattranslator','INFOPLIST_FILE'", "'PRODUCT_BUNDLE_IDENTIFIER':'app.kattranslator.voicelab','INFOPLIST_FILE'")
replace("'app.kattranslator.uitests'", "'app.kattranslator.voicelab.uitests'")
replace("objects[project]['targets'].append(widget_target)\n", "")
replace("objects[target]['dependencies'].append(obj('widget-dependency',isa='PBXTargetDependency',target=widget_target))\n", "")
replace("objects[target]['buildPhases'].append(widget_embed)\n", "")
generator.write_text(s)
subprocess.run([sys.executable, str(generator)], cwd=src, check=True)
print("Prepared", src, "from", commit)
