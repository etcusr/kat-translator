#!/usr/bin/env python3
"""Check the actual packaged notice bytes, not just project resource declarations."""
import argparse
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def packaged_notice(path):
    path = Path(path)
    if path.is_dir():
        candidates = [path / 'ThirdPartyNotices.txt', path / 'Contents/Resources/ThirdPartyNotices.txt']
        matches = [p for p in candidates if p.is_file()]
        if len(matches) != 1:
            raise ValueError('Expected one top-level app notice resource')
        return matches[0].read_bytes()
    with zipfile.ZipFile(path) as archive:
        names = [n for n in archive.namelist() if n == 'assets/ThirdPartyNotices.txt'
                 or (n.startswith('Payload/') and len(n.split('/')) == 3
                     and n.split('/')[1].endswith('.app') and n.endswith('/ThirdPartyNotices.txt'))]
        if len(names) != 1:
            raise ValueError('Expected one top-level IPA/APK notice resource')
        return archive.read(names[0])


def verify(path, expected):
    actual = packaged_notice(path)
    if actual != expected:
        raise ValueError('Packaged notices differ from the reviewed source; rebuild the app')
    return hashlib.sha256(actual).hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', help='.app directory, IPA or APK; expand a PKG first')
    args = parser.parse_args()
    try:
        digest = verify(args.artifact, (ROOT / 'assets/bundled/ThirdPartyNotices.txt').read_bytes())
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, str(error) + '\n')
    print('Packaged notices match: ' + digest)
