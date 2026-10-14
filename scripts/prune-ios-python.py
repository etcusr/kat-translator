#!/usr/bin/env python3
"""Remove unused OpenSSL extensions from the copied iOS Python runtime.

Run after install_stdlib and before process_dylibs. Never modify vendor inputs.
Wayu uses local files; downloads use URLSession and verification uses CryptoKit.
"""
import argparse
from pathlib import Path
import shutil

MODULES = ('_ssl', '_hashlib')


def prune(app):
    app = Path(app).resolve()
    libraries = list((app / 'python/lib').glob('python3.*/lib-dynload'))
    if len(libraries) != 1 or not libraries[0].is_dir():
        raise RuntimeError('Expected one copied Python standard library')
    library = libraries[0]
    pending = []
    for name in MODULES:
        pending.extend(p for p in library.iterdir()
                       if p.name.split('.')[0] == name
                       and p.suffix in ('.so', '.fwork', '.xcprivacy'))
        framework = app / 'Frameworks' / (name + '.framework')
        if framework.exists() or framework.is_symlink():
            pending.append(framework)
    # Reject escaped paths before touching anything (including incremental builds).
    for path in [library, *pending]:
        if path.is_symlink() or app not in path.resolve().parents:
            raise RuntimeError('Refusing to prune a path outside the copied app bundle')
    for path in pending:
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    return len(pending)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    args = parser.parse_args()
    print(f'Removed {prune(args.app)} unused OpenSSL packaging entries')
