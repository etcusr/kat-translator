#!/usr/bin/env python3
"""Prepare the four espeak Piper voices via deterministic ONNX metadata suffix.
No tensor conversion: exact original bytes + ONNX ModelProto metadata_props (field 14).
"""
import json,pathlib,hashlib,subprocess,shutil
R=pathlib.Path(__file__).resolve().parents[2]; O=R/'.build/tts-round2'; D=R/'model-store/downloads/tts-round2'; S=R/'docs/research/tts-round2-2026-10-07'
def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def varint(n):
 b=bytearray()
 while n>=128:b.append((n&127)|128);n>>=7
 b.append(n);return bytes(b)
def field(n,b):return varint(n*8+2)+varint(len(b))+b
texts=json.loads((S/'probe-texts.json').read_text());voices=json.loads((S/'piper-shortlist.json').read_text())
for v in voices:
 if v['sherpa_archive'] or v['id']=='he':continue
 name=v['voice']; source=D/name/(name+'.onnx');cfg=D/name/(name+'.onnx.json')
 if not source.exists():continue
 config=json.loads(cfg.read_text());assert config['phoneme_type']=='espeak'
 metadata={'model_type':'vits','comment':'piper','language':config['language']['name_english'],'voice':config['espeak']['voice'],'version':'1','has_espeak':'1','has_g2pw':'0','n_speakers':str(config['num_speakers']),'sample_rate':str(config['audio']['sample_rate'])}
 suffix=b''.join(field(14,field(1,k.encode())+field(2,val.encode())) for k,val in metadata.items())
 tokens=''.join(f'{k} {val[0] if isinstance(val,list) else val}\n' for k,val in config['phoneme_id_map'].items() if k!='\n')
 folder=O/('prepared-'+v['id']);folder.mkdir(exist_ok=True);target=folder/'model.onnx';shutil.copyfile(source,target)
 with target.open('ab') as f:f.write(suffix)
 (folder/'tokens.txt').write_text(tokens)
 data=R/'.build/verified-voices/vits-piper-en_US-ljspeech-high/espeak-ng-data'
 with (O/(v['id']+'-probe.log')).open('w') as log:
  p=subprocess.run([str(O/'probe'),str(target),str(folder/'tokens.txt'),str(data),texts[v['id']],str(O/(v['id']+'-preview.wav'))],stdout=log,stderr=subprocess.STDOUT,timeout=90)
 result=json.loads((O/(v['id']+'-result.json')).read_text());result.update(id='piper-'+name,language=v['id'],title='Piper · '+name,license=v['license_note'],sourceURL=v['model_card'],kind='piper',text=texts[v['id']])
 if p.returncode:result.update(status='error',error=f'raw piper probe {p.returncode}')
 else:
  result.update(status='ok',probe=json.loads((O/(v['id']+'-probe.log')).read_text().splitlines()[-1]))
  result['parts']=[dict(result['parts'][0],id=result['id'],path='model.onnx')]
  result['piperMetadata']=metadata;result['piperPreparation']={'metadataSuffix':__import__('base64').b64encode(suffix).decode(),'tokens':tokens}
  result['manifest']=dict(id=result['id'],archiveRoot=result['id'],files=[dict(path=p.name,byteCount=p.stat().st_size,sha256=digest(p)) for p in [target,folder/'tokens.txt']])
 (O/(v['id']+'-result.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2));print(v['id'],result['status'],flush=True)
