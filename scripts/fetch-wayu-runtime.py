#!/usr/bin/env python3
"""Fetch checksum-pinned iOS Python + Wayu text frontend (not model weights).
Run this, then prepare-wayu.py, then generate-project.py before Xcode build.
"""
import hashlib,json,tarfile,urllib.request,zipfile,sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent
entries=json.loads((root/'shared/native/Wayu/dependencies.lock.json').read_text())
for entry in entries:
    if entry.get('model') and '--models' not in sys.argv:continue
    p=root/entry['path'];p.parent.mkdir(parents=True,exist_ok=True)
    def digest():
        with p.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
    if not p.exists():
        tmp=p.with_suffix(p.suffix+'.part');urllib.request.urlretrieve(entry['url'],tmp);tmp.replace(p)
    if digest()!=entry['sha256']:raise RuntimeError('Checksum mismatch: '+p.name)
    print(p.name,'verified',flush=True)
source=root/'.build/wayu-source'
for name,dest in [('tltk','tltk'),('pythainlp','pythai'),('misaki','misaki')]:
    target=source/dest
    with zipfile.ZipFile(next(source.glob(name+'-*.whl'))) as z:
        for item in z.infolist():
            if not (target/item.filename).resolve().is_relative_to(target.resolve()):raise RuntimeError('Unsafe ZIP path')
        z.extractall(target)
target=root/'Dependencies/build/wayu';target.mkdir(parents=True,exist_ok=True)
with tarfile.open(root/'model-store/downloads/Python-3.13-iOS-support.b14.tar.gz') as t:
    t.extractall(target,members=[m for m in t.getmembers() if m.name.startswith('Python.xcframework/')],filter='data')
