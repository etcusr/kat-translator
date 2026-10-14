#!/usr/bin/env python3
"""Check a built iOS app for removed OpenSSL modules and preserved hash fallbacks.

Usage: python3 scripts/validation/check_ios_openssl.py APP
Scans all Mach-O images for known implementation markers and linked libraries.
This is a packaging check, not a legal export classification or device test.
"""
import json
from pathlib import Path
import subprocess
import sys


def check(app):
    app = Path(app)
    if not (app / 'Info.plist').is_file():
        raise RuntimeError('Expected a built iOS application')
    for name in ('_ssl', '_hashlib'):
        if (app / 'Frameworks' / (name + '.framework')).exists():
            raise RuntimeError('Excluded framework is still packaged: ' + name)
        for path in (app / 'python').rglob(name + '.*'):
            if path.suffix in ('.so', '.fwork'):
                raise RuntimeError('Excluded Python extension is still packaged: ' + str(path.relative_to(app)))
    fallbacks = ('_md5', '_sha1', '_sha2', '_sha3', '_blake2')
    for name in fallbacks:
        if not (app / 'Frameworks' / (name + '.framework') / name).is_file():
            raise RuntimeError('Missing built-in hash implementation: ' + name)
    markers = (b'OpenSSL 3.', b'_OPENSSL_init_crypto\0', b'_SSL_new\0',
               b'_EVP_EncryptInit_ex\0', b'_OpenSSL_version\0')
    count = 0
    for path in app.rglob('*'):
        if not path.is_file():
            continue
        with path.open('rb') as source:
            magic = source.read(4)
            if magic not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
                             b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
                             b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'):
                continue
            data = source.read()
        count += 1
        if any(marker in data for marker in markers):
            raise RuntimeError('OpenSSL implementation marker: ' + str(path.relative_to(app)))
        links = subprocess.check_output(['xcrun', 'otool', '-L', str(path)], text=True)
        if any(name in links.lower() for name in ('libssl', 'libcrypto', 'openssl.framework')):
            raise RuntimeError('OpenSSL library dependency: ' + str(path.relative_to(app)))
    if count == 0:
        raise RuntimeError('No Mach-O binaries inspected')
    return {'macho_images_checked': count, 'openssl_markers': 0,
            'openssl_library_dependencies': 0, 'hash_fallbacks': list(fallbacks)}


if __name__ == '__main__':
    print(json.dumps(check(sys.argv[1]), indent=2))
