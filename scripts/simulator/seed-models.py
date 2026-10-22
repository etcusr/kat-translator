#!/usr/bin/env python3
"""APFS-clone existing RU/EN test assets into Kat's dedicated simulator only."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--whisper', type=Path, required=True, help='Existing large-v3-turbo Q8_0 file')
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[2]
MAC = Path.home() / 'Library/Application Support/OfflineTranslator'
def capture(*args):
    return subprocess.check_output(args, text=True).strip()
devices = json.loads(capture('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
choices = [d for group in devices.values() for d in group if d['name'] == 'Kat iPhone 17 Pro' and d['state'] == 'Booted' and d.get('deviceTypeIdentifier') == 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro']
if len(choices) != 1: raise SystemExit('Boot exactly one Kat iPhone 17 Pro simulator first.')
device = choices[0]['udid']
container = Path(capture('xcrun', 'simctl', 'get_app_container', device, 'app.kattranslator', 'data'))
expected = Path.home() / 'Library/Developer/CoreSimulator/Devices' / device / 'data/Containers/Data/Application'
if not container.is_relative_to(expected): raise SystemExit('Unexpected simulator container')
subprocess.run(['xcrun', 'simctl', 'terminate', device, 'app.kattranslator'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
dest = container / 'Library/Application Support/OfflineTranslator'
libc = ctypes.CDLL(None, use_errno=True)
clonefile = libc.clonefile
clonefile.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
clonefile.restype = ctypes.c_int
count = 0
logical = 0
def clone(source, target):
    global count, logical
    if source.is_symlink() or not source.is_file(): raise SystemExit(f'Expected regular source: {source.name}')
    if target.exists() or target.is_symlink():
        if target.is_file() and not target.is_symlink() and target.stat().st_size == source.stat().st_size: return
        raise SystemExit(f'Refusing to replace existing file: {target.name}')
    target.parent.mkdir(parents=True, exist_ok=True)
    if clonefile(bytes(source), bytes(target), 0): raise OSError(ctypes.get_errno(), 'APFS clone failed; no full-copy fallback')
    assert target.stat().st_ino != source.stat().st_ino
    count += 1; logical += source.stat().st_size

whisper = args.whisper.resolve()
sha = '317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1'
if whisper.stat().st_size != 874188075: raise SystemExit('Wrong Whisper size')
with whisper.open('rb') as f:
    if hashlib.file_digest(f, 'sha256').hexdigest() != sha: raise SystemExit('Wrong Whisper digest')
for ident in ['index-translate-9b-q4km', 'index-translate-2b-q4km', 'vits-piper-ru_RU-denis-medium', 'vits-piper-en_US-ljspeech-high']:
    for ext in ['.bin', '.json']: clone(MAC/'Models'/(ident+ext), dest/'Models'/(ident+ext))
for ident in ['vits-piper-ru_RU-denis-medium', 'vits-piper-en_US-ljspeech-high']:
    source = MAC/'VoicePackages'/ident
    for path in source.rglob('*'):
        if path.is_file(): clone(path, dest/'VoicePackages'/ident/path.relative_to(source))
ident = 'whisper-large-v3-turbo-q8_0'
clone(whisper, dest/'Models'/(ident+'.bin'))
receipt = dest/'Models'/(ident+'.json')
if not receipt.exists():
    receipt.write_text(json.dumps(dict(id=ident,title='Whisper large-v3-turbo · Q8',byteCount=874188075,sha256=sha,remoteURL='https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q8_0.bin?download=true')))
print(json.dumps(dict(cloned_files=count, logical_bytes=logical, full_copy_fallback=False, shared_directories=False)))
