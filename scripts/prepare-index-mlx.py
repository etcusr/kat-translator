#!/usr/bin/env python3
"""Freeze the validated Mac runtime into a build input, not a runtime host dependency."""
from pathlib import Path
import hashlib, json, shutil
root=Path(__file__).resolve().parents[1]
lab=root/'.build/mac-index-mlx-mtp'
out=root/'Dependencies/build/index-mlx/IndexPython'
out.mkdir(parents=True,exist_ok=True)
excluded={'pip','setuptools','_distutils_hack','pkg_resources','wheel','scipy','nanobind','ninja','bin','__pycache__'}
for p in (lab/'venv/lib/python3.11/site-packages').iterdir():
 if p.name in excluded or p.name.endswith(('.pyc','.pth')) or p.name.startswith(('pip-','setuptools-','wheel-','scipy-','nanobind-','ninja-')):continue
 target=out/p.name
 if p.is_dir():shutil.copytree(p,target,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc','tests','test'))
 else:shutil.copy2(p,target)
shutil.copytree(lab/'omlx/omlx',out/'omlx',dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc','tests'))
shutil.copy2(lab/'omlx/LICENSE',out/'OMLX-LICENSE')
shutil.copy2(root/'shared/native/IndexMLX/index_mlx.py',out/'index_mlx.py')
manifest=[]
for p in sorted(out.rglob('*')):
 if p.is_file():manifest.append({'path':str(p.relative_to(out)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(root/'Dependencies/build/index-mlx/runtime-files.json').write_text(json.dumps(manifest,indent=2))
print('Frozen runtime:',len(manifest),'files',sum(p['bytes'] for p in manifest),'bytes')
