#!/usr/bin/env python3
"""Build a local, non-distributable lab with explicitly supplied private input/results."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--comparison',type=Path);p.add_argument('--corpus',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[3];out=root/'.build/mac-context-terms-2026-10-20';app=out/'Kat Context Lab.app'
c=app/'Contents'
for name in ['MacOS','Resources']: (c/name).mkdir(parents=True,exist_ok=True)
(c/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='app.kattranslator.contextlab',CFBundleName='Kat Context Lab',CFBundleExecutable='KatContextLab',CFBundlePackageType='APPL',CFBundleShortVersionString='0.1',CFBundleVersion='1',LSMinimumSystemVersion='27.0',NSHighResolutionCapable=True,CFBundleIconFile='KatIcon')))
shutil.copy2(root/'apps/macos/KatIcon.icns',c/'Resources/KatIcon.icns')
shutil.copy2(a.fixture,c/'Resources/fixture.json')
if a.comparison: shutil.copy2(a.comparison,c/'Resources/comparison.json')
else: (c/'Resources/comparison.json').unlink(missing_ok=True)
if a.corpus: shutil.copy2(a.corpus,c/'Resources/corpus.json')
else: (c/'Resources/corpus.json').unlink(missing_ok=True)
(c/'Resources/workspace.txt').write_text(str(root))
subprocess.run(['xcrun','swiftc',str(root/'shared/packages/OfflineCore/Sources/OfflineCore/TranslationChunks.swift'),str(Path(__file__).with_name('Planner.swift')),'-o',str(out/'planner')],check=True)
subprocess.run(['xcrun','swiftc','-parse-as-library','-O','-module-cache-path',str(out/'module-cache'),'-target','arm64-apple-macos27.0',str(Path(__file__).with_name('Lab.swift')),'-o',str(c/'MacOS/KatContextLab')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
