#!/usr/bin/env python3
"""Assemble the reviewed license texts; this does not certify complete coverage."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'docs/licensing/2026-10-14/ios-notices'
OUTPUT = ROOT / 'assets/bundled/ThirdPartyNotices.txt'


def assemble():
    sections = [
        'Kat translator — software licenses and notices\n'
        'Kat source code: https://github.com/etcusr/kat-translator\n'
        'Kat is licensed under GPL-3.0-or-later. Third-party components retain '
        'their respective licenses. Downloadable models and voices have separate '
        'terms described in the model and voice information.\n',
        'Kat license\n\n' + (ROOT / 'LICENSE').read_text(),
    ]
    for item in json.loads((SOURCE / 'manifest.json').read_text()):
        data = (SOURCE / item['file']).read_bytes()
        if hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError('License checksum mismatch: ' + item['file'])
        sections.append(item['file'] + '\n\n' + data.decode('utf-8').replace('\r\n', '\n').replace('\r', '\n'))
    return '\n\n' + ('\n\n' + '=' * 72 + '\n\n').join(sections) + '\n'


if __name__ == '__main__':
    expected = assemble()
    if '--check' in sys.argv:
        if not OUTPUT.exists() or OUTPUT.read_text() != expected:
            raise SystemExit('Run python3 scripts/assemble-ios-notices.py')
        print('License text checksums and bundled notices match')
    else:
        OUTPUT.write_text(expected)
