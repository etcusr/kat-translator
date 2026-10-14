#!/usr/bin/env python3
"""Write assets/catalogs/opus-direction-packages.json: one package per OPUS-MT Big model direction.

Inputs are verified local CTranslate2 INT8 conversions in model-store/research/opus-pairs
(ct2-transformers-converter --quantization int8 --copy_files source.spm target.spm).
Where a public conversion is byte-identical (model.bin and both .spm), the package points to
it and the small JSON files are taken from that host (--sync-hosted downloads them).
Every other direction uses --base (a pattern with {direction}); while hosting is undecided it
contains HOSTING-PENDING and the app offers manual installation only.

Routes: sources/targets are app language ids; markers map a target to the model's
>>label<< when the model has several target languages (from each model card).
"""
import argparse, hashlib, json, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'model-store/research/opus-pairs'
FILES = ['config.json', 'model.bin', 'shared_vocabulary.json', 'source.spm', 'target.spm']
ZLE = ['ru', 'uk', 'be']
LABEL = {'ru': 'rus', 'uk': 'ukr', 'be': 'bel', 'pl': 'pol', 'cs': 'ces', 'bg': 'bul', 'hr': 'hrv', 'sl': 'slv',
         'sr': 'srp_Cyrl', 'sr-Latn': 'srp_Latn', 'da': 'dan', 'no': 'nob', 'sv': 'swe', 'is': 'isl', 'nn': 'nno',
         'fo': 'fao', 'pt': 'por', 'ar': 'ara', 'fi': 'fin', 'ca': 'cat'}
ZLS = ['bg', 'hr', 'sl', 'sr', 'sr-Latn']
GMQ = ['da', 'fo', 'is', 'nn', 'no', 'sv']
# (direction, sources, targets, needs marker). Order is routing priority: specific models first.
# en-ko/ko-en are omitted: their separate-vocabulary conversion produced garbage on the Mac screen.
DIRECTIONS = [
    *[d for lang in ['de', 'fr', 'es', 'it'] for d in [(f'zle-{lang}', ZLE, [lang], False), (f'{lang}-zle', [lang], ZLE, True)]],
    ('zle-pt', ['ru', 'uk'], ['pt'], False), ('pt-zle', ['pt'], ['ru', 'uk'], True),
    ('zle-fi', ['ru', 'uk'], ['fi'], False), ('fi-zle', ['fi'], ['ru', 'uk'], True),
    ('zle-zle', ZLE, ZLE, True),
    ('zle-zlw', ZLE, ['cs', 'pl'], True), ('zlw-zle', ['cs', 'pl'], ZLE, True),
    # zle-zls into srp_Latn produced broken diacritics (æ for ć) on the Mac screen; Latin Serbian is source-only.
    ('zle-zls', ZLE, ['bg', 'hr', 'sl', 'sr'], True), ('zls-zle', ZLS, ZLE, True),
    ('zle-gmq', ['ru', 'uk'], ['da', 'no', 'sv'], True), ('gmq-zle', ['da', 'is', 'no', 'sv'], ['ru', 'uk'], True),
    *[(f'en-{lang}', ['en'], [lang], False) for lang in ['es', 'fr', 'it', 'bg', 'el', 'et', 'hu', 'lt', 'lv', 'ro', 'tr']],
    ('en-pt', ['en'], ['pt'], True), ('en-ar', ['en'], ['ar'], True), ('en-fi', ['en'], ['fi'], True),
    ('en-gmq', ['en'], GMQ, True), ('en-ces_slk', ['en'], ['cs'], False), ('en-cat_oci_spa', ['en'], ['ca'], True),
    *[(f'{lang}-en', [lang], ['en'], False) for lang in ['fr', 'it', 'ar', 'bg', 'el', 'et', 'fi', 'hu', 'lt', 'lv', 'tr', 'he']],
    ('cat_oci_spa-en', ['es', 'ca'], ['en'], False), ('ces_slk-en', ['cs'], ['en'], False), ('zlw-en', ['pl'], ['en'], False),
    ('sh-en', ['bs', 'hr', 'sr', 'sr-Latn'], ['en'], False), ('zls-en', ['bg', 'mk', 'sl'], ['en'], False),
    ('gmq-en', GMQ, ['en'], False),
]
HOSTED = {  # direction -> (repo, revision, subdirectory)
    **{f'{l}-zle': (f'NothingSoftware/opus-mt-tc-big-{l}-zle-ct2-int8', r, '') for l, r in
       [('de', '85f12ad6bb475170231c23a5e1496bde74c870d1'), ('fr', '6ccda3a9ceeff3712c147e5295d71ef4bf7c17eb'),
        ('es', '11e36db004be103470368d8070060462c8cddef3')]},
    **{d: ('crash-sv/scribe-translate-ct2', '366ea5f4bd2bc417a7430006408a0c6cd72a9f91', f'opus-mt-tc-big-{d}-ct2/')
       for d in ['en-es', 'en-fr', 'en-it', 'en-pt', 'fr-en', 'it-en', 'cat_oci_spa-en']},
}

def sha(path):
    with path.open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()

def hosted_url(direction, name):
    repo, rev, sub = HOSTED[direction]
    return f'https://huggingface.co/{repo}/resolve/{rev}/{sub}{name}?download=true'

def hosted_matches(direction):
    repo, rev, sub = HOSTED[direction]
    with urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/revision/{rev}?blobs=true', timeout=60) as r:
        blobs = {s['rfilename']: (s.get('lfs') or {}).get('sha256') for s in json.load(r)['siblings']}
    return all(blobs.get(sub + n) == sha(SOURCE/direction/n) for n in ['model.bin', 'source.spm', 'target.spm'])

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base', required=True, help='URL prefix pattern; {direction} is replaced, file name appended')
    p.add_argument('--sync-hosted', action='store_true', help='Compare with public hosts and copy their small files locally')
    p.add_argument('--check', action='store_true')
    a = p.parse_args()
    hosted = set()
    for direction in HOSTED:
        if (SOURCE/direction/'model.bin').exists() and (not a.sync_hosted or hosted_matches(direction)):
            hosted.add(direction)
            if a.sync_hosted:
                for n in ['config.json', 'shared_vocabulary.json']:
                    with urllib.request.urlopen(hosted_url(direction, n), timeout=60) as r: (SOURCE/direction/n).write_bytes(r.read())
    packages = []
    for direction, sources, targets, marked in DIRECTIONS:
        parts = []
        for name in FILES:
            path = SOURCE/direction/name
            url = hosted_url(direction, name) if direction in hosted else a.base.format(direction=direction).rstrip('/') + '/' + name + '?download=true'
            parts.append({'id': f'opus-{direction}-{name.replace(".", "-")}', 'path': f'{direction}/{name}', 'remoteURL': url,
                          'byteCount': path.stat().st_size, 'sha256': sha(path)})
        packages.append({'id': f'opus-tc-big-{direction.replace("_", "-")}-int8', 'direction': direction,
                         'sources': sources, 'targets': targets,
                         'markers': {t: f'>>{LABEL[t]}<<' for t in targets} if marked else {},
                         'license': 'CC-BY-4.0', 'sourceURL': f'https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-{direction}', 'parts': parts})
    body = json.dumps(packages, ensure_ascii=False, indent=1) + '\n'
    out = ROOT/'assets/catalogs/opus-direction-packages.json'
    if a.check:
        assert out.read_text() == body, 'opus-direction-packages.json is stale'
    else:
        out.write_text(body)
    print(f'{len(packages)} OPUS directions ({len(hosted)} hosted), {sum(sum(x["byteCount"] for x in p["parts"]) for p in packages)} bytes')

if __name__ == '__main__':
    main()
