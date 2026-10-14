#!/usr/bin/env python3
"""Copy verified local voice weights and receipts over USB. Never changes voice preferences.
Existing matching-size files are left to the app's hash validation; completion requires
an in-app readiness check after launch. No translations or ASR weights are transferred.
"""
import argparse,hashlib,json,pathlib,re,subprocess,urllib.parse
R=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--device',required=True);a.add_argument('--bundle-id',default='app.kattranslator');a.add_argument('--copy',action='store_true');args=a.parse_args()
O=R/'.build/voice-transfer';O.mkdir(exist_ok=True)
def device(*tail,output=None):
 cmd=['xcrun','devicectl',*tail]
 if output:cmd+=['--json-output',str(output)]
 r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,check=True,timeout=180)
 return r
prefix=['--device',args.device,'--domain-type','appDataContainer','--domain-identifier',args.bundle_id]
device('device','info','details','--device',args.device,output=O/'connection.json')
assert json.loads((O/'connection.json').read_text())['result']['connectionProperties']['transportType']=='wired','USB cable required; not falling back to Wi-Fi'
device('device','info','files',*prefix,'--subdirectory','Library/Application Support/OfflineTranslator/Models','--no-recurse',output=O/'before.json')
existing={f['name']:f for f in json.loads((O/'before.json').read_text())['result']['files']}
voices=json.loads((R/'assets/catalogs/additional-voices.json').read_text());descriptors=[]
for voice in voices:
 for p in voice['parts']:descriptors.append({**{k:p[k] for k in ['id','remoteURL','byteCount','sha256']},'title':voice['title']})
oldids=set('vits-piper-ru_RU-denis-medium vits-piper-en_US-ljspeech-high vits-piper-ru_RU-irina-medium vits-piper-en_US-lessac-medium sherpa-onnx-supertonic-3-tts-int8-2026-05-11 vits-piper-zh_CN-huayan-medium mms-tts-ban-onnx mms-tts-ban-tokens wayu-prosody wayu-curves wayu-decoder wayu-styles'.split())
pattern=r'ModelDescriptor\(id: "([^"]+)".*?remoteURL: URL\(string: "([^"]+)"\)!.*?byteCount: ([\d_]+), sha256: "([a-f0-9]+)"'
for file in ['shared/apple/Models/ModelCatalog.swift','shared/apple/Models/WayuCatalog.swift']:
 for id,url,size,sha in re.findall(pattern,(R/file).read_text(),re.S):
  if id in oldids:descriptors.append({'id':id,'title':id,'remoteURL':url,'byteCount':int(size.replace('_','')),'sha256':sha})
assert oldids<={d['id'] for d in descriptors};assert len(descriptors)==len({d['id'] for d in descriptors})
sizes={d['byteCount'] for d in descriptors};local={}
for path in (R/'model-store/downloads').rglob('*'):
 if path.is_file() and path.stat().st_size in sizes:local.setdefault(path.stat().st_size,[]).append(path)
plan=[]
for d in descriptors:
 id=d['id'];present=existing.get(id+'.bin',{}).get('metadata',{}).get('size')==d['byteCount'] and id+'.json' in existing
 if present:plan.append({'id':id,'action':'already-present','bytes':d['byteCount']});continue
 source=None
 for candidate in local.get(d['byteCount'],[]):
  with candidate.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
  if digest==d['sha256']:source=candidate;break
 assert source, 'No verified cached copy: '+id
 plan.append({'id':id,'action':'copy','bytes':d['byteCount'],'source':str(source),'descriptor':d})
(O/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
print('Voice components:',len(plan),'copy bytes:',sum(p['bytes'] for p in plan if p['action']=='copy'),flush=True)
if not args.copy:raise SystemExit(0)
completed=[]
for p in plan:
 if p['action']=='copy':
  receipt=O/(p['id']+'.json');receipt.write_text(json.dumps(p['descriptor'],ensure_ascii=False))
  for source,name in [(p['source'],p['id']+'.bin'),(str(receipt),p['id']+'.json')]:
   device('device','copy','to',*prefix,'--source',source,'--destination','Library/Application Support/OfflineTranslator/Models/'+name)
 completed.append({k:v for k,v in p.items() if k!='descriptor'});(O/'completed.json').write_text(json.dumps(completed,ensure_ascii=False,indent=2)+'\n')
 print(len(completed),'/',len(plan),p['action'],p['id'],flush=True)
device('device','info','files',*prefix,'--subdirectory','Library/Application Support/OfflineTranslator/Models','--no-recurse',output=O/'after.json')
actual={f['name']:f for f in json.loads((O/'after.json').read_text())['result']['files']}
assert all(actual[p['id']+'.bin']['metadata']['size']==p['bytes'] and p['id']+'.json' in actual for p in plan)
print('All voice components present with expected sizes and receipts. App must validate hashes and install packages.',flush=True)
