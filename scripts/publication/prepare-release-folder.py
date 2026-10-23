#!/usr/bin/env python3
"""Assemble local Store copy and validated platform screenshots; never upload or replace an existing folder."""
import argparse,json,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--copy-root',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();source=a.copy_root.resolve();out=a.output.resolve()
if not source.is_relative_to(ROOT/'docs/publication'):p.error('Copy must be under docs/publication')
if not out.is_relative_to(ROOT/'dist/store'):p.error('Output must be under ignored dist/store')
release=json.loads((source/'release.json').read_text())
manifest=ROOT/'site/assets/screenshots'/source.name/'manifest.json'
rows=json.loads(manifest.read_text())['captures']
# Validate the entire set before reserving a new destination.
images=[r for r in rows if r['platform']=='ios' or r['kind'].startswith('full app window')]
ios_counts = {language: sum(r['platform']=='ios' and r['language']==language for r in images) for language in ('en','ru','es','tr')}
if len(set(ios_counts.values())) != 1 or next(iter(ios_counts.values())) not in (6,7):
 raise SystemExit('Expected six or seven iPhone screenshots in each of four languages')
for row in images:
 if row['platform']!='ios' and (row['width'],row['height']) not in ((1440,900),(2880,1800)):
  raise SystemExit('Unexpected Mac screenshot dimensions')
for row in images:
 path=(ROOT/'site'/row['path']).resolve()
 if not path.is_relative_to(ROOT/'site/assets/screenshots') or not path.is_file():raise SystemExit('Invalid screenshot path')
out.mkdir(parents=True,exist_ok=False)
blocks=['KAT TRANSLATOR — LOCAL RELEASE PREPARATION\nNot uploaded. Existing Mac review untouched.\n']
for platform in ('ios','macos'):
 for language in ('en','ru','es','tr'):
  for field in ('name','subtitle','promotional_text','description','keywords','whats-new','support_url','marketing_url','privacy_policy_url'):
   file=source/platform/language/(field+'.txt')
   blocks.append(f'\n=== {platform} / {language} / {field} ===\n'+file.read_text().strip()+'\n')
 blocks.append(f'\n=== {platform} / Review notes ===\n'+(source/platform/'review_notes.txt').read_text())
(out/'APP-STORE-TEXTS.txt').write_text(''.join(blocks))
for row in images:
 dest=out/'screenshots'/('iPhone' if row['platform']=='ios' else 'Mac')/row['language']/Path(row['path']).name;dest.parent.mkdir(parents=True,exist_ok=True)
 shutil.copyfile(ROOT/'site'/row['path'],dest)
shutil.copyfile(source/'release.json',out/'release.json')
shutil.copyfile(manifest,out/'screenshot-manifest.json')
(out/'STATUS.ru.md').write_text('Актуальный статус подготовки и ограничения: [отчёт в репозитории](' + str(source/'README.ru.md') + ').\n')
(out/'README.txt').write_text('Local preparation only. iPhone screenshots are raw 1206x2622 simulator captures. Voice iPhone scenes may use prepared presentation state, as recorded in the screenshot manifest; they are not engine acceptance tests. Full Mac window captures are included when present; native Quick setup view previews are excluded from Store screenshots. Build/export status and pending work are listed in release.json and the linked repository report. Consult docs/publication/'+source.name+'/README.md in the repository for current status. No upload, review or publication performed.\n')
print(out.relative_to(ROOT))
