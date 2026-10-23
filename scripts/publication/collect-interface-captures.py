#!/usr/bin/env python3
"""Collect named XCTest screenshots and native Mac previews without altering pixels."""
import argparse, hashlib, json, re, shutil, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--ios',type=Path,required=True,help='xcresult exported attachments directory')
p.add_argument('--mac',type=Path,required=True,help='native preview directory')
p.add_argument('--mac-windows', type=Path, help='XCTest attachments from full-window Voice/Text/Language captures')
p.add_argument('--ios-presentation', type=Path, help='Simulator presentation-state attachments (Voice/Image; no inference)')
p.add_argument('--date',required=True)
a=p.parse_args()
if not re.fullmatch(r'\d{4}-\d{2}-\d{2}',a.date):p.error('Expected YYYY-MM-DD')
out=ROOT/'site/assets/screenshots'/a.date
rows=[]
prior=json.loads((out/'manifest.json').read_text()) if (out/'manifest.json').exists() else {}
prior_rows={r['path']:r for r in prior.get('captures',[])}
def save(source,platform,language,name,kind,version):
    data=source.read_bytes()
    if data[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('Expected PNG')
    width,height=struct.unpack('>II',data[16:24])
    dest=out/platform/language/(name+'.png');dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(source,dest)
    rows.append(dict(path=str(dest.relative_to(ROOT/'site')),platform=platform,language=language,screen=name,
                     kind=kind,version=version,width=width,height=height,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
    for key in ('captureDate','sourceState'):
        if key in prior_rows.get(rows[-1]['path'],{}):rows[-1][key]=prior_rows[rows[-1]['path']][key]
for case in json.loads((a.ios/'manifest.json').read_text()):
    for item in case['attachments']:
        match=re.match(r'publication-ios-(en|ru|es|tr)-(\d\d-[a-z-]+)_',item['suggestedHumanReadableName'])
        if match and not item.get('isAssociatedWithFailure'):
            save(a.ios/item['exportedFileName'],'ios',*match.groups(),'iPhone 17 Pro simulator screenshot','1.1.0 (73)')
for source in sorted(a.mac.glob('*/*.png')):
    if source.parent.name in ('en','ru','es','tr') and (not a.mac_windows or source.stem == '04-quick-setup'):
        save(source,'macos-preview',source.parent.name,source.stem,'native view preview; not a desktop screenshot','0.7.0 (68)')
if a.mac_windows:
    for case in json.loads((a.mac_windows/'manifest.json').read_text()):
        for item in case['attachments']:
            match=re.match(r'publication-mac-(en|ru|es|tr)-(0[123]-[a-z-]+)_', item['suggestedHumanReadableName'])
            if match and not item.get('isAssociatedWithFailure'):
                save(a.mac_windows/item['exportedFileName'],'macos-preview',*match.groups(),
                     'full app window screenshot; real translation; diagnostics off','0.7.0 (68), updated development source')
                rows[-1]['captureDate']='2026-10-23'
                rows[-1]['sourceState']='UI source shared with Store 1.1.0 (79); file-import audio fixture, not live microphone'
    # Remove only the three explicitly replaced publication assets, never arbitrary files.
    if len([r for r in rows if r['kind'].startswith('full app')]) != 12:
        raise SystemExit('Expected 12 full Mac window captures')
    for language in ('en','ru','es','tr'):
        for name in ('01-settings','02-models-and-voices','03-voices'):
            (out/'macos-preview'/language/(name+'.png')).unlink(missing_ok=True)
if a.ios_presentation:
    count = 0
    for case in json.loads((a.ios_presentation/'manifest.json').read_text()):
        for item in case['attachments']:
            match = re.match(r'publication-ios-(en|ru|es|tr)-(0[78]-(?:voice|image))_', item['suggestedHumanReadableName'])
            if match and not item.get('isAssociatedWithFailure'):
                save(a.ios_presentation/item['exportedFileName'], 'ios', *match.groups(),
                     'presentation fixture rendered by app UI; no inference', '1.1.0 (73), presentation-only simulator build')
                rows[-1]['captureDate'] = '2026-10-23'
                rows[-1]['sourceState'] = 'Isolated source snapshot; prepared original and translation; no ASR/MT/camera/playback acceptance'
                count += 1
    if count != 8: raise SystemExit(f'Expected 8 presentation captures, got {count}')
expected = 48 if a.ios_presentation else 40
if len(rows)!=expected:raise SystemExit(f'Expected {expected} captures, got {len(rows)}')
if len({r['path'] for r in rows}) != len(rows): raise SystemExit('Duplicate capture paths')
(out/'manifest.json').write_text(json.dumps({'date':a.date,'updatedAt':prior.get('updatedAt',a.date),'pixelEdits':'none','captures':rows},ensure_ascii=False,indent=2)+'\n')
print(f'{len(rows)} images, {sum(r["bytes"] for r in rows):,} bytes; manifest {out.relative_to(ROOT)}/manifest.json')
