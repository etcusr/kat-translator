#!/usr/bin/env python3
"""Install Kat's integration-specific disclosures for repackaged Apple SDKs.

Static libraries and bare dylibs/extensions get separate codeless resource
bundles. Framework declarations live inside their framework and are re-signed.
Vendor inputs are never modified. See Dependencies/privacy/README.md.
"""
import argparse
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PRIVACY = ROOT / 'Dependencies/privacy'


def plan(platform):
    # (required binary/resource inputs, manifest destination, source, new resource bundle)
    if platform == 'ios':
        return [
            (['OfflineTranslator'], f'{name}Privacy.bundle/PrivacyInfo.xcprivacy', f'ios/{name}.xcprivacy', f'{name}Privacy.bundle')
            for name in ('ONNXRuntime', 'SherpaOnnx')
        ] + [(['FluidAudio_FluidAudio.bundle/Info.plist'],
              'FluidAudio_FluidAudio.bundle/PrivacyInfo.xcprivacy', 'ios/FluidAudio.xcprivacy', None)]
    if platform != 'macos':
        raise ValueError('Unsupported platform')
    resources = 'Contents/Resources/'
    frameworks = 'Contents/Frameworks/'
    sdks = {
        'ONNXRuntime': [frameworks + 'libonnxruntime.dylib'],
        'SherpaOnnx': [frameworks + 'libsherpa-onnx-c-api.dylib'],
        'Protobuf': [resources + 'IndexPython/google/_upb/_message*.so'],
        'SentencePiece': [resources + runtime + '/sentencepiece/_sentencepiece*.so' for runtime in ('IndexPython', 'OpusPython')],
        'PyTorch': [resources + 'OpusPython/torch/lib/libtorch_cpu.dylib'],
    }
    return [
        (inputs, resources + name + 'Privacy.bundle/Contents/Resources/PrivacyInfo.xcprivacy',
         'macos/NoCollection.xcprivacy', resources + name + 'Privacy.bundle')
        for name, inputs in sdks.items()
    ] + [
        (['Contents/MacOS/Kat translator'], resources + 'PrivacyInfo.xcprivacy', 'macos/NoCollection.xcprivacy', None),
        ([frameworks + 'OpusRuntime.framework/Versions/A/OpusRuntime'],
         frameworks + 'OpusRuntime.framework/Versions/A/Resources/PrivacyInfo.xcprivacy', 'macos/NoCollection.xcprivacy', None),
        ([resources + 'FluidAudio_FluidAudio.bundle/Contents/Info.plist'],
         resources + 'FluidAudio_FluidAudio.bundle/Contents/Resources/PrivacyInfo.xcprivacy', 'macos/NoCollection.xcprivacy', None),
    ]


def install(app, platform, *, identity, runner=subprocess.run):
    app = Path(app)
    pending = []
    stale_resource_signatures = []
    for inputs, destination, source, bundle in plan(platform):
        for pattern in inputs:
            if not any(p.is_file() for p in app.glob(pattern)):
                raise RuntimeError(f'Missing SDK input: {pattern}')
        data = (PRIVACY / source).read_bytes()
        declaration = plistlib.loads(data)
        if (set(declaration) != {'NSPrivacyTracking', 'NSPrivacyTrackingDomains',
                                 'NSPrivacyCollectedDataTypes', 'NSPrivacyAccessedAPITypes'}
                or declaration['NSPrivacyTracking'] is not False
                or declaration['NSPrivacyTrackingDomains'] != []
                or declaration['NSPrivacyCollectedDataTypes'] != []
                or not isinstance(declaration['NSPrivacyAccessedAPITypes'], list)):
            raise RuntimeError(f'Review changed privacy declaration: {source}')
        target = app / destination
        if target.exists() and plistlib.loads(target.read_bytes()) != declaration:
            raise RuntimeError(f'Upstream privacy declaration changed: {destination}')
        pending.append((target, data))
        if bundle:
            info = {'CFBundleIdentifier': 'app.kattranslator.privacy.' + Path(bundle).stem,
                    'CFBundleName': Path(bundle).stem, 'CFBundlePackageType': 'BNDL',
                    'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0'}
            path = app / bundle / ('Contents/Info.plist' if platform == 'macos' else 'Info.plist')
            if path.exists() and plistlib.loads(path.read_bytes()) != info:
                raise RuntimeError(f'Unexpected privacy resource bundle: {bundle}')
            pending.append((path, plistlib.dumps(info)))
    if platform == 'macos':
        # Normal Mac builds may leave a signed SwiftPM resource bundle; store
        # packaging already strips these seals. Adding a manifest invalidates it.
        fluid = app / 'Contents/Resources/FluidAudio_FluidAudio.bundle/Contents'
        signature = fluid / '_CodeSignature'
        if signature.exists():
            if plistlib.loads((fluid / 'Info.plist').read_bytes()).get('CFBundleExecutable'):
                raise RuntimeError('Expected codeless FluidAudio resources; review changed SDK layout')
            stale_resource_signatures.append(signature)
    # Validate everything before modifying any bundle.
    for target, data in pending:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    for signature in stale_resource_signatures:
        shutil.rmtree(signature)
    if platform == 'macos' and identity is not None:
        framework = app / 'Contents/Frameworks/OpusRuntime.framework'
        runner(['/usr/bin/codesign', '--force', '--sign', identity,
                *shlex.split(os.environ.get('OTHER_CODE_SIGN_FLAGS', '')),
                '--timestamp=none', '--preserve-metadata=identifier,entitlements,flags',
                '--generate-entitlement-der', str(framework)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--platform', choices=('ios', 'macos'), required=True)
    args = parser.parse_args()
    identity = None
    if os.environ.get('CODE_SIGNING_ALLOWED', 'YES') != 'NO':
        identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY')
        if not identity:
            parser.error('Signing enabled but EXPANDED_CODE_SIGN_IDENTITY is empty')
    install(args.app, args.platform, identity=identity)
    print(f'Installed {len(plan(args.platform))} SDK/app privacy manifests ({args.platform})')


if __name__ == '__main__':
    main()
