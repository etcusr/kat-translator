#!/usr/bin/env python3
"""Install audited declarations into embedded iOS frameworks, then re-sign them.

Runs after Xcode embedding and Python extension conversion. Never edits vendor
XCFrameworks or the installed app. See Dependencies/privacy/ios/README.md.
"""
import argparse
import os
from pathlib import Path
import plistlib
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_ROOT = ROOT / 'Dependencies/privacy/ios'
FRAMEWORKS = ('Python', 'TranslationRuntime', 'OmniVoiceRuntime', '_hashlib', '_ssl')


def install(app, *, identity, runner=subprocess.run):
    pending = []
    # Validate the whole set first, so missing inputs and upstream changes do not
    # produce a partially modified bundle or silently replace new disclosures.
    for name in FRAMEWORKS:
        bundle = Path(app) / 'Frameworks' / (name + '.framework')
        if not (bundle / name).is_file() or not (bundle / 'Info.plist').is_file():
            raise RuntimeError(f'Missing embedded framework: {name}')
        source = MANIFEST_ROOT / (name + '.xcprivacy')
        data = source.read_bytes()
        declaration = plistlib.loads(data)
        required = {'NSPrivacyTracking', 'NSPrivacyTrackingDomains',
                    'NSPrivacyCollectedDataTypes', 'NSPrivacyAccessedAPITypes'}
        if not required.issubset(declaration):
            raise RuntimeError(f'Incomplete privacy declaration: {name}')
        target = bundle / 'PrivacyInfo.xcprivacy'
        if target.exists() and plistlib.loads(target.read_bytes()) != declaration:
            raise RuntimeError(f'Upstream privacy declaration changed: {name}; review before replacing')
        pending.append((bundle, target, data))
    for bundle, target, data in pending:
        target.write_bytes(data)
        if identity is not None:
            runner(['/usr/bin/codesign', '--force', '--sign', identity,
                    *shlex.split(os.environ.get('OTHER_CODE_SIGN_FLAGS', '')),
                    '--timestamp=none', '--preserve-metadata=identifier,entitlements,flags',
                    '--generate-entitlement-der', str(bundle)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    args = parser.parse_args()
    identity = None
    if os.environ.get('CODE_SIGNING_ALLOWED', 'YES') != 'NO':
        identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY')
        if not identity:
            parser.error('Signing enabled but EXPANDED_CODE_SIGN_IDENTITY is empty')
    install(args.app, identity=identity)
    print(f'Installed {len(FRAMEWORKS)} framework privacy manifests')


if __name__ == '__main__':
    main()
