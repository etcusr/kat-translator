#!/usr/bin/env python3
"""Sign Kat's distribution of pinned upstream SDKs without changing their payload.

This is a distributor signature, not an upstream signature or source rebuild.
The input archives and every original package file are checked before and after
signing. Output is separate from production SDKs and must be promoted explicitly.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'docs/licensing/2026-10-14/sdk-provenance.json'


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify_payload(sdk, archive, expected_hash):
    if sha256(archive) != expected_hash:
        raise ValueError('Upstream archive checksum mismatch')
    expected = {}
    with zipfile.ZipFile(archive) as z:
        prefix = sdk.name + '/'
        for member in z.infolist():
            if member.is_dir() or not member.filename.startswith(prefix):
                continue
            relative = Path(member.filename[len(prefix):])
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe archive path')
            if relative.parts[0] == '_CodeSignature':
                raise ValueError('Upstream signature must not be replaced by this recipe')
            if relative.as_posix() in expected:
                raise ValueError('Duplicate archive member')
            expected[relative.as_posix()] = hashlib.sha256(z.read(member)).hexdigest()
    if not expected:
        raise ValueError('SDK absent from archive')
    actual = {}
    for path in sdk.rglob('*'):
        if path.is_symlink():
            raise ValueError('Unexpected SDK symlink')
        if path.is_file() and path.relative_to(sdk).parts[0] != '_CodeSignature':
            actual[path.relative_to(sdk).as_posix()] = sha256(path)
    if actual != expected:
        raise ValueError('SDK payload differs from pinned upstream archive')
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--identity', required=True, help='Apple signing identity from the keychain')
    args = parser.parse_args()
    entries = json.loads(LOCK.read_text())['sdks']
    # Preflight all inputs before creating or signing any output.
    payloads = [verify_payload(ROOT / e['sdk'], ROOT / e['archive'], e['sha256']) for e in entries]
    args.output.mkdir(parents=True, exist_ok=False)
    records = []
    for entry, payload in zip(entries, payloads):
        source = ROOT / entry['sdk']
        relative = Path(entry['sdk']).relative_to('Dependencies/build')
        target = args.output / relative
        shutil.copytree(source, target)
        subprocess.run(['codesign', '--force', '--timestamp', '--sign', args.identity, str(target)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target)], check=True)
        assert verify_payload(target, ROOT / entry['archive'], entry['sha256']) == payload
        records.append(dict(sdk=relative.as_posix(), archiveSHA256=entry['sha256'],
                            payload=payload, signatureVerified=True,
                            signatureRole='Kat distributor; not upstream supplier',
                            upstreamPayloadUnchanged=True))
    (args.output / 'signed-sdk-payloads.json').write_text(json.dumps(records, indent=2) + '\n')
    print('Verified and signed all three SDK distributions; original payloads unchanged')


if __name__ == '__main__':
    main()
