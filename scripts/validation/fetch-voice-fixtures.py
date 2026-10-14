#!/usr/bin/env python3
"""Download pinned app voices for local validation; never uploads or contacts an inference service."""
import hashlib, pathlib, re, urllib.request
root = pathlib.Path(__file__).resolve().parents[2]
catalog = (root / 'shared/apple/Models/ModelCatalog.swift').read_text()
pattern = r'static let (\w+) = ModelDescriptor\(id: "([^"]+)", title: "[^"]+",\s*remoteURL: URL\(string: "([^"]+)"\)!,\s*byteCount: ([\d_]+), sha256: "([a-f0-9]+)"'
for name, identity, url, size, digest in re.findall(pattern, catalog):
    if not name.endswith('Voice'): continue
    path = root / 'model-store/downloads' / (identity + '.tar.bz2')
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        temporary = path.with_suffix('.partial')
        urllib.request.urlretrieve(url, temporary)
        temporary.rename(path)
    assert path.stat().st_size == int(size.replace('_', '')), path
    with path.open('rb') as f: assert hashlib.file_digest(f, 'sha256').hexdigest() == digest, path
    print(identity, 'verified', flush=True)
