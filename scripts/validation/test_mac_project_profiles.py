#!/usr/bin/env python3
"""Regression (audit 22.10 B18): a non-modern Mac profile must never rewrite the tracked Xcode project."""
from pathlib import Path
import hashlib, os, shutil, subprocess, sys
root = Path(__file__).resolve().parents[2]
tracked = root/'apps/macos/KatTranslatorMac.xcodeproj/project.pbxproj'
generator = root/'scripts/generate-macos-project.py'
digest = lambda: hashlib.sha256(tracked.read_bytes()).hexdigest()
def generate(**env):
    return subprocess.run([sys.executable, str(generator)], env={**os.environ, **env}, capture_output=True, text=True)
before = digest(); failures = []
try:
    plain = generate(KAT_MAC_PROFILE='macos15')
    if plain.returncode == 0: failures.append('macos15 without KAT_MAC_PROJECT_DIR was accepted')
    if digest() != before: failures.append('macos15 generation rewrote the tracked project')
    out_dir = root/'.build/test-macos15-project'; shutil.rmtree(out_dir, ignore_errors=True)
    copy = generate(KAT_MAC_PROFILE='macos15', KAT_MAC_PROJECT_DIR=str(out_dir))
    if copy.returncode != 0: failures.append('macos15 into KAT_MAC_PROJECT_DIR failed: ' + copy.stderr[-500:])
    elif not (out_dir/'KatTranslatorMac.xcodeproj/project.pbxproj').exists():
        failures.append('KAT_MAC_PROJECT_DIR is ignored: no project written there')
    elif 'KAT_MAC_PROFILE = "macos15"' not in (out_dir/'KatTranslatorMac.xcodeproj/project.pbxproj').read_text():
        failures.append('untracked project is not the macos15 profile')
    if digest() != before: failures.append('KAT_MAC_PROJECT_DIR generation rewrote the tracked project')
    listed = subprocess.run(['true']) if not out_dir.exists() else subprocess.run(['xcodebuild', '-list', '-project', str(out_dir/'KatTranslatorMac.xcodeproj')], capture_output=True, text=True)
    if out_dir.exists() and (listed.returncode != 0 or 'KatTranslatorMac' not in listed.stdout): failures.append('untracked project does not open: ' + listed.stderr[-300:])
    shutil.rmtree(out_dir, ignore_errors=True)
    script = (root/'scripts/build-macos15-26.sh').read_text()
    if 'KAT_MAC_PROJECT_DIR' not in script or 'apps/macos/KatTranslatorMac.xcodeproj' in script:
        failures.append('build-macos15-26.sh still builds the tracked project')
finally:
    if digest() != before:  # the unfixed generator rewrote it: restore the modern project
        generate(KAT_MAC_PROFILE='modern')
        print('tracked project restored:', digest() == before)
if failures: print('FAIL\n- ' + '\n- '.join(failures)); sys.exit(1)
print('OK')
