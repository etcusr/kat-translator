#!/usr/bin/env python3
"""Collect named XCTest screenshots and native Mac previews without altering pixels."""
import argparse, hashlib, json, re, shutil, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--ios',type=Path,required=True,help='xcresult exported attachments directory')
p.add_argument('--mac',type=Path,required=True,help='native preview directory')
p.add_argument('--date',required=True)
a=p.parse_args()
if not re.fullmatch(r'\d{4}-\d{2}-\d{2}',a.date):p.error('Expected YYYY-MM-DD')
out=ROOT/'site/assets/screenshots'/a.date
rows=[]
def save(source,platform,language,name,kind,version):
    data=source.read_bytes()
    if data[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('Expected PNG')
    width,height=struct.unpack('>II',data[16:24])
    dest=out/platform/language/(name+'.png');dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(source,dest)
    rows.append(dict(path=str(dest.relative_to(ROOT/'site')),platform=platform,language=language,screen=name,
                     kind=kind,version=version,width=width,height=height,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
for case in json.loads((a.ios/'manifest.json').read_text()):
    for item in case['attachments']:
        match=re.match(r'publication-ios-(en|ru|es|tr)-(\d\d-[a-z-]+)_',item['suggestedHumanReadableName'])
        if match and not item.get('isAssociatedWithFailure'):
            save(a.ios/item['exportedFileName'],'ios',*match.groups(),'iPhone 17 Pro simulator screenshot','1.1.0 (73)')
for source in sorted(a.mac.glob('*/*.png')):
    if source.parent.name in ('en','ru','es','tr'):
        save(source,'macos-preview',source.parent.name,source.stem,'native view preview; not a desktop screenshot','0.7.0 (68)')
if len(rows)!=40:raise SystemExit(f'Expected 24 iOS captures and 16 Mac previews, got {len(rows)}')
(out/'manifest.json').write_text(json.dumps({'date':a.date,'pixelEdits':'none','captures':rows},ensure_ascii=False,indent=2)+'\n')
print(f'{len(rows)} images, {sum(r["bytes"] for r in rows):,} bytes; manifest {out.relative_to(ROOT)}/manifest.json')
