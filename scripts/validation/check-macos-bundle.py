#!/usr/bin/env python3
"""Reject accidental host-library dependencies in a standalone Mac bundle."""
from pathlib import Path
import json, subprocess, sys, re, plistlib
root = Path(sys.argv[1]); issues = []; count = 0
info = plistlib.loads((root/'Contents/Info.plist').read_bytes())
minimum = info.get('LSMinimumSystemVersion', '15.0')
version = lambda value: tuple(int(x) for x in (value.split('.')+['0','0'])[:3])
rpath_issues = []; deployment_issues = []
magic = {bytes.fromhex(x) for x in ('cffaedfe', 'feedfacf', 'cafebabe', 'bebafeca')}
for path in root.rglob('*'):
    if path.is_symlink() or not path.is_file(): continue
    with path.open('rb') as stream:
        if stream.read(4) not in magic: continue
    count += 1
    for line in subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()[1:]:
        if not line.startswith('\t'): continue  # skip architecture headings of universal binaries
        dependency = line.strip().split(' (')[0]
        if dependency.startswith('/') and not dependency.startswith(('/System/', '/usr/lib/')):
            issues.append({'file': str(path.relative_to(root)), 'dependency': dependency})
    commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
    for rpath in re.findall(r'cmd LC_RPATH\n.*?\n\s*path (.*?) \(offset', commands):
        if rpath.startswith('/') and not rpath.startswith(('/System/', '/usr/lib/')):
            rpath_issues.append({'file':str(path.relative_to(root)), 'rpath':rpath})
    for required in re.findall(r'\bminos ([0-9.]+)', commands):
        if version(required) > version(minimum):
            deployment_issues.append({'file':str(path.relative_to(root)), 'requiredMacOS':required})
print(json.dumps({'machOFiles': count, 'minimumMacOS':minimum, 'externalNonSystemDependencies': issues,
                 'externalNonSystemRPaths':rpath_issues, 'librariesExceedingMinimumMacOS':deployment_issues}, indent=2))
if issues or rpath_issues or deployment_issues: sys.exit(1)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(root)], check=True)
