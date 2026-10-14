#!/usr/bin/env python3
"""Five-phrase screen: native synthesis + independent Meta ASR; fail closed per language.
ASR disagreements may be recognition errors: they exclude a route, never prove bad TTS.
"""
import array,json,pathlib,re,subprocess,unicodedata,wave
R=pathlib.Path(__file__).resolve().parents[2];D=R/'docs/research/omnivoice-2026-10-07';O=R/'.build/omnivoice/coverage';O.mkdir(exist_ok=True)
asr=R/'.build/speech-expansion/sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-v2-int8-2026-02-05'
def normalized(s):return ''.join(c for c in unicodedata.normalize('NFD',s.lower()) if c.isalnum())
def cer(a,b):
 a,b=normalized(a),normalized(b);row=list(range(len(b)+1))
 for i,x in enumerate(a,1):
  new=[i]
  for j,y in enumerate(b,1):new.append(min(new[-1]+1,row[j]+1,row[j-1]+(x!=y)))
  row=new
 return row[-1]/max(1,len(a))
def phrase_passed(r):
 return r.get('exitCode')==0 and r.get('audioSeconds',0)>=.8 and r.get('clippedFraction',1)<.01 and r.get('quietFraction',1)<.65 and bool(r.get('recognized')) and r.get('cer',1)<=.20
results=[]
for language in json.loads((D/'coverage-corpus.json').read_text())['languages']:
 code=language['code'];items=[]
 for i,phrase in enumerate(language['phrases']):
  key=f'{code}-{i+1}';path=O/(key+'.json');wav=O/(key+'.wav');text=phrase['text']
  if path.exists() and json.loads(path.read_text()).get('text')==text:
   cached=json.loads(path.read_text());cached['passed']=phrase_passed(cached);path.write_text(json.dumps(cached,ensure_ascii=False,indent=2)+'\n');items.append(cached);continue
  result={'code':code,'phrase':i+1,'text':text,'passed':False}
  with (O/(key+'.log')).open('w') as f:
   try:p=subprocess.run([str(R/'.build/omnivoice/cancel-probe'),str(R/'model-store/downloads/omnivoice/omnivoice-base-Q8_0.gguf'),str(R/'model-store/downloads/omnivoice/omnivoice-tokenizer-Q8_0.gguf'),language['runtimeLanguage'],text,str(wav)],stdout=f,stderr=subprocess.STDOUT,timeout=90);status=p.returncode
   except subprocess.TimeoutExpired:status=124
  result['exitCode']=status
  if status==0:
   lines=(O/(key+'.log')).read_text().splitlines();stats=[json.loads(l) for l in lines if l.startswith('{"language"')];result.update(stats[-1])
   with wave.open(str(wav)) as w:pcm=array.array('h',w.readframes(w.getnframes()))
   result['clippedFraction']=sum(abs(x)>=32760 for x in pcm)/max(1,len(pcm));result['quietFraction']=sum(abs(x)<100 for x in pcm)/max(1,len(pcm))
   with (O/(key+'-asr.log')).open('w') as err:
    try:r=subprocess.run([str(R/'.build/speech-expansion/omni-probe'),str(asr/'model.int8.onnx'),str(asr/'tokens.txt'),str(wav)],stdout=subprocess.PIPE,stderr=err,text=True,timeout=30)
    except subprocess.TimeoutExpired:r=None
   hypothesis=r.stdout.strip() if r and r.returncode==0 else '';result['recognized']=hypothesis;result['cer']=round(cer(text,hypothesis),4)
   result['passed']=phrase_passed(result)
  path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');items.append(result)
  print(key,'PASS' if result['passed'] else 'SKIP',result.get('cer'),result.get('recognized',''),flush=True)
 passed=all(x['passed'] for x in items) and sum(x.get('cer',1) for x in items)/5<=.10
 results.append({'code':code,'runtimeLanguage':language['runtimeLanguage'],'passed':passed,'phrases':items})
 (D/'coverage-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
 print('LANGUAGE',code,passed,flush=True)
print('ACCEPTED',[x['code'] for x in results if x['passed']],flush=True)
