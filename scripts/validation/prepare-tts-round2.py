#!/usr/bin/env python3
"""Pinned, sequential download + native runtime probes. No inference servers.
Generated results are candidates; only reviewed successes enter the app catalog.
"""
import csv, hashlib, json, pathlib, shutil, subprocess, tarfile, time, urllib.request, sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
RESEARCH=ROOT/'docs/research/tts-round2-2026-10-07'
OUT=ROOT/'.build/tts-round2'; OUT.mkdir(exist_ok=True)
CACHE=ROOT/'model-store/downloads/tts-round2';CACHE.mkdir(exist_ok=True)
PIPER_SHA='c10ece1aade47bb51c153c893d14e5bf8e5b7117'
MMS_SHA='4f49fc254f11ddb0e35fbf25b6e48b04463a6779'
def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def fetch(url,path,expected=None):
 if not path.exists():
  for attempt in range(3):
   try:
    req=urllib.request.Request(url,headers={'User-Agent':'OfflineTranslator-validation'})
    with urllib.request.urlopen(req,timeout=90) as r, path.with_suffix('.partial').open('wb') as f:shutil.copyfileobj(r,f,1024*1024)
    path.with_suffix('.partial').replace(path);break
   except Exception:
    if attempt==2:raise
    time.sleep(2)
 if expected:assert digest(path)==expected,path
 return dict(remoteURL=url,byteCount=path.stat().st_size,sha256=digest(path))
def probe(lang,folder,model,tokens,data,text):
 wave=OUT/(lang+'-preview.wav'); log=OUT/(lang+'-probe.log')
 with log.open('w') as f:r=subprocess.run([str(OUT/'probe'),str(model),str(tokens),str(data),text,str(wave)],stdout=f,stderr=subprocess.STDOUT,timeout=90)
 if r.returncode:raise RuntimeError(f'probe exit {r.returncode}: {log}')
 return json.loads(log.read_text().splitlines()[-1])
voices=json.loads((RESEARCH/'piper-shortlist.json').read_text())
allp=json.loads((RESEARCH/'sources/piper-voices.json').read_text())
assets={a['name']:a for a in json.loads((RESEARCH/'sources/sherpa-tts-release.json').read_text())['assets']}
texts=json.loads((RESEARCH/'probe-texts.json').read_text())
rows=list(csv.DictReader((RESEARCH/'candidates.csv').open()))
items=voices+[dict(id=r['id'],language=r['language'],mms=r['mms_exact_iso']) for r in rows if r['mms_exact_iso'] and not r['piper']]
if '--refresh-samples' in sys.argv:
 items=[dict(id=r['id'],language=r['language'],mms=r['mms_exact_iso']) for r in rows if r['id'] in ['cnh','hif','os']]
if '--mms-fallback' in sys.argv:
 items=[dict(id=r['id'],language=r['language'],mms=r['mms_exact_iso']) for r in rows if r['id'] in ['bn','he','mr']]
results=[]
for item in items:
 lang=item['id'];result=dict(language=lang,text=texts[lang]); resultfile=OUT/(lang+'-result.json')
 if resultfile.exists():
  old=json.loads(resultfile.read_text())
  if old.get('status')=='ok' and old.get('text')==texts[lang]:results.append(old);print(lang,'cached',flush=True);continue
 try:
  if item.get('sherpa_archive'):
   name=pathlib.Path(item['sherpa_archive']).name; asset=assets[name]; archive=CACHE/name
   result.update(id='vits-piper-'+item['voice'],title='Piper · '+item['voice'],license=item['license_note'],sourceURL=item['model_card'],kind='archive')
   part=fetch(item['sherpa_archive'],archive,(asset.get('digest')or'').removeprefix('sha256:')or None);part.update(id=result['id'],path='archive');result['parts']=[part]
   expanded=OUT/'expanded';expanded.mkdir(exist_ok=True)
   with tarfile.open(archive) as tar:tar.extractall(expanded,filter='data')
   folder=expanded/result['id'];model=next(folder.glob('*.onnx'));tokens=folder/'tokens.txt';data=folder/'espeak-ng-data'
   result['manifest']=dict(id=result['id'],archiveRoot=result['id'],files=[dict(path=str(p.relative_to(folder)),byteCount=p.stat().st_size,sha256=digest(p)) for p in sorted(folder.rglob('*')) if p.is_file()])
   result['probe']=probe(lang,folder,model,tokens,data,texts[lang]);shutil.rmtree(folder)
  elif 'mms' in item:
   code=item['mms'];folder=CACHE/('mms-'+code);folder.mkdir(exist_ok=True)
   result.update(id='mms-tts-'+code+'-onnx',title='Meta MMS · '+code,license='CC BY-NC 4.0',sourceURL='https://huggingface.co/facebook/mms-tts-'+code,kind='files',parts=[])
   for name,suffix in [('model.onnx','-onnx'),('tokens.txt','-tokens')]:
    part=fetch(f'https://huggingface.co/willwade/mms-tts-multilingual-models-onnx/resolve/{MMS_SHA}/{code}/{name}',folder/name)
    part.update(id='mms-tts-'+code+suffix,path=name);result['parts'].append(part)
   tokens=(folder/'tokens.txt').read_text();chars={line.rsplit(' ',1)[0] for line in tokens.splitlines()}
   # Missing alphabetic characters must be reviewed, not silently discarded by VITS.
   result['missingLetters']=sorted({c for c in texts[lang].lower() if c.isalpha() and c not in chars})
   result['manifest']=dict(id=result['id'],archiveRoot=result['id'],files=[dict(path=p['path'],byteCount=p['byteCount'],sha256=p['sha256']) for p in result['parts']])
   result['probe']=probe(lang,folder,folder/'model.onnx',folder/'tokens.txt','',texts[lang])
  else:
   folder=CACHE/item['voice'];folder.mkdir(exist_ok=True);result.update(kind='raw-piper',id='piper-'+item['voice'],parts=[])
   for path,meta in allp[item['voice']]['files'].items():
    if path.endswith(('.onnx','.json')):
     part=fetch(f'https://huggingface.co/rhasspy/piper-voices/resolve/{PIPER_SHA}/{path}',folder/pathlib.Path(path).name)
     result['parts'].append(part)
   result['status']='needs-preparation';resultfile.write_text(json.dumps(result,ensure_ascii=False,indent=2));results.append(result);print(lang,'raw downloaded',flush=True);continue
  result['status']='ok'
 except Exception as e:result['status']='error';result['error']=str(e)
 resultfile.write_text(json.dumps(result,ensure_ascii=False,indent=2));results.append(result);print(lang,result['status'],result.get('error',''),flush=True)
(OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
