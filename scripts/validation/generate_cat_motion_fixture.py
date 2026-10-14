#!/usr/bin/env python3
"""Regenerate Android trajectory reference from the current iOS motion implementation."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[2]
core = root / "shared/packages/OfflineCore/Sources/OfflineCore"
work = root / ".build/cat-reference"
work.mkdir(parents=True, exist_ok=True)
source = work / "main.swift"
source.write_text("\n".join(p.read_text() for p in [
    core / "CatProgressMotion.swift", core / "CatLoadingPlay.swift",
    root / "tests/fixtures/android/cat-motion-reference.swift"]))
result = subprocess.run(["swift", "-module-cache-path", str(work / "module-cache"), str(source)], check=True, capture_output=True, text=True)
(root / "tests/fixtures/android/cat-motion-ios.json").write_text(result.stdout)
