#!/usr/bin/env python3
"""Publish only successfully probed, reviewed alphabet-compatible voice routes."""
import json,pathlib,re,shutil,subprocess
from voice_catalog_capabilities import update_capabilities
R=pathlib.Path(__file__).resolve().parents[2];O=R/'.build/tts-round2'
results=[json.loads(p.read_text()) for p in sorted(O.glob('*-result.json'))]
valid=[x for x in results if x.get('status')=='ok' and not x.get('missingLetters')]
fields=['id','language','title','license','sourceURL','kind','parts','piperPreparation']
voices=[{k:v for k,v in x.items() if k in fields} for x in valid]
catalog=R/'assets/catalogs/additional-voices.json'
existing=json.loads(catalog.read_text()) if catalog.exists() else []
voices += [v for v in existing if v.get('languageAliases')]
catalog.write_text(json.dumps(voices,ensure_ascii=False,indent=2)+'\n')
p=R/'assets/catalogs/voice-manifests.json'; manifests=json.loads(p.read_text()); ids={x['id'] for x in valid};oldids={x['id'] for x in results if 'id' in x}
manifestlist=[x for x in manifests if x['id'] not in oldids]+[x['manifest'] for x in valid]
p.write_text(json.dumps(manifestlist,ensure_ascii=False,indent=2)+'\n')
p=R/'shared/packages/OfflineCore/Sources/OfflineCore/LanguageSelection.swift';s=p.read_text()
scope={v['language'] for v in existing if not v.get('languageAliases')} | {v['language'] for v in results}
s=update_capabilities(s,scope,voices)
p.write_text(s)
previews=[]
for x in valid:
 dst=O/(x['id']+'-preview.wav');shutil.copyfile(O/(x['language']+'-preview.wav'),dst);previews.append(str(dst))
subprocess.run([str(R/'.build/normalize-language-previews'),*previews],cwd=R,check=True)
report=[{k:v for k,v in x.items() if k not in ['manifest','parts','piperMetadata','piperPreparation']} for x in results]
(R/'docs/benchmarks/tts-round2/results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f'Published {len(valid)} new voices; {len(results)-len(valid)} require further work')
