#!/usr/bin/env python3
"""Check embedded iOS framework deployment metadata against actual Mach-O targets."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d+(?:\.\d+){0,2}', value):
        raise ValueError('Missing or invalid MinimumOSVersion')
    parts = [int(x) for x in value.split('.')]
    return tuple(parts + [0] * (3 - len(parts)))


def check(app):
    app_min = version(plistlib.loads((app / 'Info.plist').read_bytes()).get('MinimumOSVersion'))
    bundles = sorted((app / 'Frameworks').glob('*.framework'))
    if not bundles:
        raise ValueError('No embedded frameworks')
    for bundle in bundles:
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        declared = version(info.get('MinimumOSVersion'))
        if not (version('8.0') <= declared <= app_min):
            raise ValueError(f'Invalid framework deployment range: {bundle.name}')
        executable = info.get('CFBundleExecutable', '')
        if not executable or Path(executable).name != executable:
            raise ValueError(f'Invalid framework executable: {bundle.name}')
        output = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(bundle / executable)], text=True)
        minimums = re.findall(r'^\s+minos\s+(\S+)', output, re.M)
        if not minimums or any(version(v) > declared for v in minimums):
            raise ValueError(f'Framework plist understates binary deployment target: {bundle.name}')
    return len(bundles)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    print(f'Checked deployment metadata for {check(args.app)} embedded frameworks')
