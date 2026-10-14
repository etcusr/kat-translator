#!/usr/bin/env python3
"""Fetch the exact shared OPUS package once, without platform-specific model copies."""
import hashlib
import json
import os
from pathlib import Path
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / 'model-store/downloads/opus-big'
parts = json.loads((ROOT / 'assets/catalogs/opus-package.json').read_text())

def valid(path, part):
    if not path.is_file() or path.stat().st_size != part['byteCount']:
        return False
    with path.open('rb') as file:
        digest = hashlib.file_digest(file, 'sha256').hexdigest()
    return digest == part['sha256']

for part in parts:
    target = TARGET / part['path']
    assert TARGET.resolve() in target.resolve().parents
    target.parent.mkdir(parents=True, exist_ok=True)
    if valid(target, part):
        print('Verified', part['path'], flush=True)
        continue
    temporary = target.with_name(target.name + '.partial')
    for attempt in range(3):
        try:
            offset = temporary.stat().st_size if temporary.exists() else 0
            if offset > part['byteCount']:
                temporary.unlink()
                offset = 0
            request = urllib.request.Request(part['remoteURL'], headers={'Range': f'bytes={offset}-'} if offset else {})
            with urllib.request.urlopen(request, timeout=60) as response:
                append = offset > 0 and response.status == 206
                with temporary.open('ab' if append else 'wb') as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
                        if output.tell() > part['byteCount']:
                            raise ValueError('Upstream exceeded pinned size')
                    output.flush()
                    os.fsync(output.fileno())
            if not valid(temporary, part):
                temporary.unlink(missing_ok=True)
                raise ValueError('Pinned size/SHA-256 mismatch: ' + part['path'])
            os.replace(temporary, target)
            print('Downloaded and verified', part['path'], flush=True)
            break
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)
print('Shared OPUS package:', TARGET, flush=True)
