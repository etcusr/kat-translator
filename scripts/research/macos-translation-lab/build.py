#!/usr/bin/env python3
"""Build a separate local experiment; never replace the installed Kat app."""
import plistlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / ".build/mac-system-translation-2026-10-20"
APP = OUT / "Kat Translation Lab.app"
CONTENTS = APP / "Contents"
for directory in ("MacOS", "Resources"):
    (CONTENTS / directory).mkdir(parents=True, exist_ok=True)
info = dict(CFBundleIdentifier="app.kattranslator.translationlab",
            CFBundleName="Kat Translation Lab", CFBundleDisplayName="Kat Translation Lab",
            CFBundleExecutable="KatTranslationLab", CFBundlePackageType="APPL",
            CFBundleShortVersionString="0.1", CFBundleVersion="1",
            LSMinimumSystemVersion="27.0", NSHighResolutionCapable=True,
            CFBundleIconFile="KatIcon")
(CONTENTS / "Info.plist").write_bytes(plistlib.dumps(info))
shutil.copy2(ROOT / "apps/macos/KatIcon.icns", CONTENTS / "Resources/KatIcon.icns")
shutil.copy2(ROOT / "tests/fixtures/mac-system-translation.json", CONTENTS / "Resources/cases.json")
long_cases = json.loads((ROOT / "tests/fixtures/mac-long-context.json").read_text())
long_cases += json.loads((ROOT / "tests/fixtures/mac-chunk-boundary-context.json").read_text())
(CONTENTS / "Resources/long-cases.json").write_text(json.dumps(long_cases, ensure_ascii=False))
(CONTENTS / "Resources/workspace.txt").write_text(str(ROOT))
subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-O",
                "-module-cache-path", str(OUT / "module-cache"),
                "-target", "arm64-apple-macos27.0",
                str(Path(__file__).with_name("Lab.swift")),
                "-o", str(CONTENTS / "MacOS/KatTranslationLab")], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(APP)], check=True)
print(APP)
