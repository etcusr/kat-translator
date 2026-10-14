#!/usr/bin/env python3
"""Publish smoke-tested routes; quality exclusions remain explicit and reproducible."""
import json,pathlib,re,subprocess
R=pathlib.Path(__file__).resolve().parents[2];D=R/'docs/research/omnivoice-2026-10-07';O=R/'.build/omnivoice'
results=json.loads((D/'coverage-results.json').read_text())
valid=[r for r in results if r['passed']]
assert valid, 'No five-phrase verified route; do not publish OmniVoice yet'
aliases={r['code']:r['runtimeLanguage'] for r in valid}
parts=json.loads((D/'assets.json').read_text());voice={'id':'omnivoice-q8-base','language':next(iter(aliases)),'languageAliases':aliases,'title':'OmniVoice Q8','license':'CC BY-NC 4.0','sourceURL':'https://huggingface.co/k2-fsa/OmniVoice','kind':'files','parts':parts}
p=R/'assets/catalogs/additional-voices.json';voices=json.loads(p.read_text());voices=[v for v in voices if v['id']!=voice['id']]+[voice];p.write_text(json.dumps(voices,ensure_ascii=False,indent=2)+'\n')
p=R/'assets/catalogs/voice-manifests.json';manifests=json.loads(p.read_text());manifests=[v for v in manifests if v['id']!=voice['id']]+[{'id':voice['id'],'archiveRoot':voice['id'],'files':[{k:p[k] for k in ['path','byteCount','sha256']} for p in parts]}];p.write_text(json.dumps(manifests,ensure_ascii=False,indent=2)+'\n')
p=R/'shared/packages/OfflineCore/Sources/OfflineCore/LanguageSelection.swift';s=p.read_text()
# Only uncovered candidates can change; preserve the non-Omni capability baseline.
for candidate in json.loads((D/'coverage-corpus.json').read_text())['languages']:
 code=candidate['code'];value='true' if code in aliases else 'false'
 s=re.sub(r'(\.init\(id: "'+re.escape(code)+r'",[^\n]*hasVoice: )(true|false)',lambda m:m.group(1)+value,s)
p.write_text(s)
previews=[]
for code in aliases:
 source=O/'coverage'/(code+'-1.wav');destination=O/('omnivoice-q8-base-'+code+'-preview.wav')
 import shutil
 shutil.copyfile(source,destination);previews.append(str(destination))
subprocess.run([str(R/'.build/normalize-language-previews'),*previews],cwd=R,check=True)
(D/'published-routes.json').write_text(json.dumps({'aliases':aliases,'rejected':[r['code'] for r in results if not r['passed']],'note':'Only previously uncovered languages. Five-phrase finite audio, artifacts and independent ASR screen. No native-speaker quality certification.'},ensure_ascii=False,indent=2)+'\n')
print('Published',len(aliases),'OmniVoice routes')
