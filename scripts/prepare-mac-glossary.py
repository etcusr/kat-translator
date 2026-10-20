#!/usr/bin/env python3
"""Prepare checksum-pinned, pure-Python glossary dependencies (build time only)."""
from pathlib import Path
import hashlib
import json
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Dependencies/build/mac-glossary'

def prepare():
    cache = ROOT / '.build/mac-glossary-wheels'
    cache.mkdir(parents=True, exist_ok=True)
    libraries = OUT / 'libraries'
    libraries.mkdir(parents=True, exist_ok=True)
    for row in json.loads((ROOT / 'shared/native/IndexMLX/glossary-dependencies.json').read_text()):
        archive = cache / row['file']
        if not archive.exists(): urllib.request.urlretrieve(row['url'], archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != row['sha256']:
            raise ValueError('Glossary wheel checksum mismatch: ' + row['file'])
        with zipfile.ZipFile(archive) as wheel:
            for name in wheel.namelist():
                if Path(name).is_absolute() or '..' in Path(name).parts: raise ValueError('Unsafe wheel member')
            wheel.extractall(libraries)
    records = []
    for path in sorted(libraries.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            records.append(dict(path=str(path.relative_to(libraries)), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    (OUT / 'files.json').write_text(json.dumps(records, indent=2) + '\n')
    print('Prepared glossary dependencies:', len(records), 'files')

if __name__ == '__main__': prepare()
