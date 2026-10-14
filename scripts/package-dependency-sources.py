#!/usr/bin/env python3
"""Package only hash-locked dependency inputs into independently readable tar parts.

No downloads, extraction, execution of upstream code, or implicit publication.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'docs/licensing/2026-10-14/dependency-sources.json'
SOURCES = ROOT / 'dist/licensing/dependency-sources-2026-10-14'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def checked_inputs(lock, source):
    entries = json.loads(lock.read_text())['archives']
    seen = set()
    for entry in entries:
        name = entry['file']
        if not name or Path(name).name != name or name in {'.', '..'} or name in seen:
            raise ValueError(f'Unsafe or duplicate input: {name}')
        seen.add(name)
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'Not a regular input: {name}')
        if path.stat().st_size != entry['bytes'] or digest(path) != entry['sha256']:
            raise ValueError(f'Input mismatch: {name}')
    return sorted(entries, key=lambda e: e['file'])


def add_bytes(archive, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    info.mtime = 0
    archive.addfile(info, io.BytesIO(data))


def package(lock, source, output, limit=900_000_000):
    entries = checked_inputs(lock, source)
    # Fail before creating anything if an input cannot fit the selected part size.
    if any(e['bytes'] > limit for e in entries):
        raise ValueError('An input exceeds the part payload limit')
    output.mkdir(parents=True, exist_ok=False)
    parts, group, size = [], [], 0
    groups = []
    for entry in entries:
        if group and size + entry['bytes'] > limit:
            groups.append(group)
            group, size = [], 0
        group.append(entry)
        size += entry['bytes']
    if group:
        groups.append(group)
    for number, group in enumerate(groups, 1):
        path = output / f'dependency-sources-part-{number:02d}.tar'
        with tarfile.open(path, 'w', format=tarfile.USTAR_FORMAT) as archive:
            add_bytes(archive, 'dependency-sources.json', lock.read_bytes())
            for entry in group:
                info = tarfile.TarInfo('sources/' + entry['file'])
                info.size, info.mode, info.mtime = entry['bytes'], 0o644, 0
                with (source / entry['file']).open('rb') as stream:
                    archive.addfile(info, stream)
        # Read back every packaged member; the lock alone is not an output check.
        with tarfile.open(path) as archive:
            for entry in group:
                stream = archive.extractfile('sources/' + entry['file'])
                if stream is None or hashlib.file_digest(stream, 'sha256').hexdigest() != entry['sha256']:
                    raise ValueError(f'Packaged input mismatch: {entry["file"]}')
        parts.append(dict(file=path.name, bytes=path.stat().st_size,
                          sha256=digest(path), inputs=[e['file'] for e in group]))
    manifest = dict(schema=1, scope='Upstream source inputs; not a binary reproducibility certification',
                    lockSHA256=digest(lock), inputCount=len(entries), parts=parts)
    (output / 'publication-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(''.join(f'{p["sha256"]}  {p["file"]}\n' for p in parts))
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = package(LOCK, SOURCES, args.output)
    print(f'Packaged and verified {result["inputCount"]} inputs in {len(result["parts"])} parts')
