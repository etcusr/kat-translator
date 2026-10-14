#!/usr/bin/env python3
"""Stamp a deterministic diagnostic fingerprint into the built app, before signing.

This identifies source/resources and build settings, not the signed app's bytes.
Downloaded models, user data, signing credentials and timestamps are excluded.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile

BUILD_SETTINGS = (
    'CONFIGURATION', 'ARCHS', 'PLATFORM_NAME', 'SDK_VERSION', 'SDK_PRODUCT_BUILD_VERSION',
    'XCODE_VERSION_ACTUAL', 'XCODE_PRODUCT_BUILD_VERSION', 'SWIFT_VERSION',
    'SWIFT_OPTIMIZATION_LEVEL', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS',
    'GCC_PREPROCESSOR_DEFINITIONS', 'IPHONEOS_DEPLOYMENT_TARGET', 'MACOSX_DEPLOYMENT_TARGET', 'KAT_MAC_PROFILE',
    'ENABLE_TESTABILITY', 'OTHER_SWIFT_FLAGS', 'OTHER_CFLAGS', 'OTHER_CPLUSPLUSFLAGS',
)
IGNORED = {'.DS_Store', '.git', '.build', '__pycache__', 'tests', 'Config', 'xcuserdata'}


def source_files(root, platform):
    folders = ['shared/apple', 'shared/native', 'assets', 'apps/macos' if platform == 'macosx' else 'apps/ios']
    files = set()
    for folder in folders:
        files.update((root / folder).rglob('*'))
    for package in (root / 'shared/packages').glob('*'):
        files.update((package / 'Sources').rglob('*'))
        files.update(package.glob('Package.*'))
    files.update((root / 'Dependencies').glob('*.lock.json'))
    files.update((root / 'scripts').glob('*.py'))
    files.update((root / 'scripts').glob('*.sh'))
    project = root / ('apps/macos/KatTranslatorMac.xcodeproj' if platform == 'macosx' else 'apps/ios/OfflineTranslator.xcodeproj')
    files.add(project / 'project.pbxproj')
    files.update((project / 'project.xcworkspace/xcshareddata/swiftpm').glob('Package.resolved'))
    return sorted((p for p in files if p.is_file()
                   and not any(part in IGNORED for part in p.relative_to(root).parts)
                   and p.suffix not in {'.pyc', '.pyo'}
                   and not p.name.startswith('test_')),
                  key=lambda p: p.relative_to(root).as_posix())


def build_identity(root: Path, platform: str, environment: dict) -> dict:
    if platform not in {'macosx', 'iphoneos', 'iphonesimulator'}:
        raise ValueError('Unsupported build platform: ' + platform)
    settings = {key: environment[key] for key in BUILD_SETTINGS if key in environment}
    settings['PLATFORM_NAME'] = platform
    digest = hashlib.sha256(b'kat-build-identity-v1\0')
    digest.update(json.dumps(settings, sort_keys=True, separators=(',', ':')).encode())
    files = source_files(root, platform)
    if not files:
        raise ValueError('No application sources found')
    for path in files:
        # Per-file hashes and delimited paths make concatenation unambiguous.
        file_hash = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                file_hash.update(chunk)
        digest.update(b'\0' + path.relative_to(root).as_posix().encode() + b'\0' + file_hash.digest())
    full = digest.hexdigest()
    prefix = 'mac' if platform == 'macosx' else 'sim' if platform == 'iphonesimulator' else 'ios'
    return {'schema': 1, 'identifier': prefix + '-' + full[:16], 'sha256': full,
            'platform': platform, 'configuration': environment.get('CONFIGURATION', ''),
            'sourceFileCount': len(files)}


def write_identity(output: Path, identity: dict):
    data = plistlib.dumps(identity, sort_keys=True)
    if output.is_file() and output.read_bytes() == data:
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(data)
    try:
        temporary.chmod(0o644)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--platform', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    identity = build_identity(args.root.resolve(), args.platform, os.environ)
    write_identity(args.output, identity)
    print('Kat build ID: ' + identity['identifier'])
