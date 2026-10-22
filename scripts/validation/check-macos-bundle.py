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
# Every @rpath/@loader_path/@executable_path dependency must resolve inside the bundle; a missing
# library otherwise passes this check and only fails in dyld at launch.
executable_dir = root/'Contents/MacOS'
def expand(value, owner):
    return Path(value.replace('@loader_path', str(owner.parent)).replace('@executable_path', str(executable_dir)))
unresolved = []; foreign_architectures = []; team_issues = []; test_bundles = set()
def team(path):
    detail = subprocess.run(['codesign', '-dv', str(path)], capture_output=True, text=True).stderr
    match = re.search(r'^TeamIdentifier=(.+)$', detail, re.M)
    return match.group(1).strip() if match else None
app_team = team(root)
images = {}
for path in root.rglob('*'):
    if path.is_symlink() or not path.is_file(): continue
    with path.open('rb') as stream:
        if stream.read(4) not in magic: continue
    relative = path.relative_to(root)
    # build-for-testing products carry XCTest bundles linked against Xcode; they are never shipped.
    if relative.parts[:2] == ('Contents', 'PlugIns') and len(relative.parts) > 2 and relative.parts[2].endswith(('.xctest', '.xctest.dSYM')):
        test_bundles.add('/'.join(relative.parts[:3])); continue
    commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
    own_id = subprocess.check_output(['otool', '-D', str(path)], text=True).splitlines()[1:]
    dependencies = [line.strip().split(' (')[0] for line in subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()[1:] if line.startswith('\t')]
    images[path.resolve()] = {'path': path, 'rpaths': [expand(r, path) for r in re.findall(r'cmd LC_RPATH\n.*?\n\s*path (.*?) \(offset', commands)],
                              'dependencies': [d for d in dependencies if d not in own_id and d.startswith('@')]}
    archs = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
    if archs != ['arm64']: foreign_architectures.append({'file': str(relative), 'architectures': archs})
    # With a real identity every nested binary must carry the same team (no stray ad-hoc signatures).
    if app_team and team(path) != app_team: team_issues.append({'file': str(relative), 'team': team(path)})
# dyld searches @rpath through the LC_RPATH of the image and of every image that loaded it, so a
# dependency counts as resolved when any loader chain inside the bundle supplies a matching rpath.
inherited = {key: list(image['rpaths']) for key, image in images.items()}
def resolve(key, dependency):
    image = images[key]
    if dependency.startswith('@rpath/'):
        for base in inherited[key]:
            candidate = base/dependency.removeprefix('@rpath/')
            if candidate.exists(): return candidate.resolve()
        return None
    candidate = expand(dependency, image['path'])
    return candidate.resolve() if candidate.exists() else None
changed = True
while changed:
    changed = False
    for key, image in images.items():
        for dependency in image['dependencies']:
            target = resolve(key, dependency)
            if target in images:
                for base in inherited[key]:
                    if base not in inherited[target]: inherited[target].append(base); changed = True
for key, image in images.items():
    for dependency in image['dependencies']:
        if resolve(key, dependency) is None:
            unresolved.append({'file': str(image['path'].relative_to(root)), 'dependency': dependency})
print(json.dumps({'machOFiles': count, 'minimumMacOS':minimum, 'externalNonSystemDependencies': issues,
                 'externalNonSystemRPaths':rpath_issues, 'librariesExceedingMinimumMacOS':deployment_issues,
                 'unresolvedBundleDependencies': unresolved, 'ignoredTestBundles': sorted(test_bundles), 'nonArm64Binaries': foreign_architectures,
                 'signingTeam': app_team, 'differentSigningTeam': team_issues}, indent=2))
if issues or rpath_issues or deployment_issues or unresolved or foreign_architectures or team_issues: sys.exit(1)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(root)], check=True)
