#!/usr/bin/env python3
import json,pathlib,re
from voice_catalog_capabilities import covered_codes
R=pathlib.Path(__file__).resolve().parents[2]
voices=json.loads((R/'assets/catalogs/additional-voices.json').read_text());manifests={p['id']:p for p in json.loads((R/'assets/catalogs/voice-manifests.json').read_text())}
languages=(R/'shared/packages/OfflineCore/Sources/OfflineCore/LanguageSelection.swift').read_text()
assert voices,'Empty expansion'
enabled=set(re.findall(r'\.init\(id: "([^"]+)",[^\n]*hasVoice: true',languages))
assert enabled==covered_codes(voices), ('Capability/route mismatch',enabled ^ covered_codes(voices))
seen=set()
for v in voices:
 assert re.search(r'\.init\(id: "'+re.escape(v['language'])+r'",[^\n]*hasVoice: true',languages),v['language']
 assert v['parts'][0]['id']==v['id']
 for code in v.get('languageAliases',{v['language']:v['language']}):
  assert re.search(r'\.init\(id: "'+re.escape(code)+r'",[^\n]*hasVoice: true',languages),code
  suffix='-'+code if v.get('languageAliases') else ''
  preview = R/'assets/bundled/VoicePreviews'/(v['id']+suffix+'.m4a')
  # A voice can ship without a sample; the UI hides its preview button.
  if preview.exists(): assert preview.stat().st_size>1000,(v['id'],code)
 assert v['id'] in manifests,v['id']
 assert len({p['path'] for p in v['parts']})==len(v['parts'])
 for p in v['parts']:
  assert p['id'] not in seen;seen.add(p['id'])
  assert re.fullmatch('[a-f0-9]{64}',p['sha256'])
  assert p['byteCount']>0 and p['remoteURL'].startswith('https://')
 if v['kind']=='files':
  assert [{k:p[k] for k in ['path','byteCount','sha256']} for p in v['parts']]==manifests[v['id']]['files']
 if v['kind']=='piper':assert v['piperPreparation']['metadataSuffix'] and v['piperPreparation']['tokens']
print('PASS:',len(voices),'additional voices, unique components, previews, manifests, capabilities')
