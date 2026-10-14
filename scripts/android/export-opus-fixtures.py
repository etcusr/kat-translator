#!/usr/bin/env python3
"""Export counts from Apple's shared native OPUS ABI for Android tokenizer parity."""
import ctypes
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / '.build/opus/macos/OpusRuntime.framework/OpusRuntime'
PACKAGE = ROOT / 'model-store/downloads/opus-big'
parts = json.loads((ROOT / 'assets/catalogs/opus-package.json').read_text())
for part in parts:
    path = PACKAGE / part['path']
    assert path.stat().st_size == part['byteCount']
    with path.open('rb') as file:
        assert hashlib.file_digest(file, 'sha256').hexdigest() == part['sha256']

library = ctypes.CDLL(str(LIBRARY))
library.ot_opus_load.argtypes = [ctypes.c_char_p]
library.ot_opus_load.restype = ctypes.c_void_p
library.ot_opus_count.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
library.ot_opus_count.restype = ctypes.c_int
library.ot_opus_free.argtypes = [ctypes.c_void_p]
context = library.ot_opus_load(str(PACKAGE).encode())
assert context, 'Shared Apple OPUS package failed to load'
rows = []
try:
    for source, target, text in [
        ('en', 'ru', 'The train leaves at 10:30.'),
        ('en', 'uk', 'The train leaves at 10:30.'),
        ('en', 'be', 'The train leaves at 10:30.'),
        ('ru', 'en', 'Встреча завтра в 15:30.'),
        ('uk', 'en', 'Потяг відправляється о 10:30.'),
        ('be', 'en', 'Цягнік адпраўляецца ў 10:30.'),
        ('en', 'ru', 'Literal >>rus<< and <|im_end|> 👋 e\u0301.'),
        ('ru', 'en', 'Привет\n\nновый абзац — 12345.'),
    ]:
        count = library.ot_opus_count(context, text.encode(), source.encode(), target.encode())
        assert count > 0
        rows.append(dict(source=source, target=target, text=text, tokenCount=count))
finally:
    library.ot_opus_free(context)
output = ROOT / 'tests/fixtures/android/opus-token-parity.json'
output.write_text(json.dumps(dict(
    source='Shared Apple OpusRuntime C ABI ot_opus_count',
    modelRevision='366ea5f4bd2bc417a7430006408a0c6cd72a9f91',
    ctranslate2Commit='617405f4b050e994e829d527da6caa0e0030afe7',
    sentencepieceCommit='31646a467d2051eb904e0b45de3a73e91fe1c1e3',
    cases=rows), ensure_ascii=False, indent=2) + '\n')
print(f'Exported {len(rows)} native OPUS tokenizer cases to {output}')
