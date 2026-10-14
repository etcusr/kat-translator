#!/usr/bin/env python3
"""Fetch and verify reviewed source archives, without executing upstream code.

The lock describes collected inputs, not a certification that release binaries
can be reproduced. See the adjacent source-kit report for remaining gaps.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'docs/licensing/2026-10-14/dependency-sources.json'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def destination(root, name):
    if Path(name).name != name or name in {'', '.', '..'}:
        raise ValueError('Archive filename must be a plain basename')
    path = root / name
    if path.is_symlink():
        raise ValueError('Refusing archive symlink: ' + name)
    return path


def collect(item, output, check=False):
    target = destination(output, item['file'])
    if target.is_file() and digest(target) == item['sha256']:
        return
    if check:
        raise ValueError('Missing or altered source: ' + item['file'])
    if not item['url'].startswith('https://'):
        raise ValueError('Only HTTPS source downloads are accepted')
    with tempfile.NamedTemporaryFile(dir=output, prefix='.source-', delete=False) as stream:
        temporary = Path(stream.name)
        try:
            request = urllib.request.Request(item['url'], headers={'User-Agent': 'Kat-source-kit/1.0'})
            with urllib.request.urlopen(request, timeout=90) as response:
                if not response.url.startswith('https://'):
                    raise ValueError('Insecure redirect')
                shutil.copyfileobj(response, stream)
            stream.close()
            if digest(temporary) != item['sha256']:
                raise ValueError('Source checksum mismatch: ' + item['file'])
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/licensing/dependency-sources-2026-10-14')
    parser.add_argument('--check', action='store_true', help='Verify locally, without network access')
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text())
    files = [item['file'] for item in lock['archives']]
    if len(files) != len(set(files)):
        raise ValueError('Duplicate source filenames')
    args.output.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        results = [executor.submit(collect, item, args.output, args.check) for item in lock['archives']]
        errors = []
        for result in results:
            try:
                result.result()
            except Exception as error:
                errors.append(str(error))
    if errors:
        raise SystemExit('\n'.join(errors))
    if not args.check:
        shutil.copyfile(LOCK, args.output / LOCK.name)
    print(f"Verified {len(files)} pinned source archives; see source-kit.md for coverage limits")


if __name__ == '__main__':
    main()
