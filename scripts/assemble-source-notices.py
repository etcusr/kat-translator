#!/usr/bin/env python3
"""Reproduce supplemental notices from checksum-pinned source archives.

Archive members are read in memory, never extracted or executed. Identical
license texts are stored once with every applicable component/path attribution.
"""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / 'docs/licensing/2026-10-14/source-notices.json'
LOCK = ROOT / 'docs/licensing/2026-10-14/dependency-sources.json'
OUTPUT = ROOT / 'docs/licensing/2026-10-14/ios-notices'


def read_members(archive, members):
    result = {}
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as source:
            for member in members:
                info = source.getinfo(member)
                if info.file_size > 2_000_000:
                    raise ValueError('Unexpectedly large notice')
                result[member] = source.read(info)
    else:
        with tarfile.open(archive) as source:
            for member in members:
                info = source.getmember(member)
                if not info.isfile() or info.size > 2_000_000:
                    raise ValueError('Not a regular notice file')
                result[member] = source.extractfile(info).read()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, default=ROOT / 'dist/licensing/dependency-sources-2026-10-14')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    lock = {r['file']: r for r in json.loads(LOCK.read_text())['archives']}
    verified = set()
    for group in json.loads(SPEC.read_text())['groups']:
        texts = {}
        current_archive = None
        payloads = {}
        for entry in group['members']:
            archive = args.sources / entry['archive']
            if archive.name != entry['archive'] or archive.is_symlink():
                raise ValueError('Unsafe archive path')
            if archive not in verified:
                with archive.open('rb') as stream:
                    sha = hashlib.file_digest(stream, 'sha256').hexdigest()
                if sha != lock[archive.name]['sha256']:
                    raise ValueError('Archive checksum mismatch: ' + archive.name)
                verified.add(archive)
            if current_archive != archive:
                payloads = read_members(archive, {e['member'] for e in group['members'] if e['archive'] == archive.name})
                current_archive = archive
            data = payloads[entry['member']]
            if hashlib.sha256(data).hexdigest() != entry['sha256']:
                raise ValueError('Notice checksum mismatch: ' + entry['member'])
            if 'slice' in entry:
                start, end = entry['slice']
                if not 0 <= start < end <= len(data):
                    raise ValueError('Invalid license comment boundaries')
                data = data[start:end]
                if not data.startswith(b'/*') or not data.endswith(b'*/'):
                    raise ValueError('Not a complete license comment')
            text = data.decode(entry.get('encoding', 'utf-8')).replace('\r\n', '\n').replace('\r', '\n')
            label = lock[archive.name]['name'] + ' — ' + entry['member']
            texts.setdefault(text, []).append(label)
        parts = [group['title'] + '\n\n' + group['scope']]
        for text, labels in texts.items():
            parts.append('\n'.join(labels) + '\n\n' + text)
        content = ('\n\n' + '=' * 72 + '\n\n').join(parts) + '\n'
        if Path(group['output']).name != group['output']:
            raise ValueError('Unsafe output path')
        target = OUTPUT / group['output']
        if args.check:
            if target.read_text() != content:
                raise ValueError('Stale generated notice: ' + target.name)
        else:
            target.write_text(content)
        print(f"{target.name}: {len(group['members'])} inputs, {len(texts)} distinct texts")


if __name__ == '__main__':
    main()
