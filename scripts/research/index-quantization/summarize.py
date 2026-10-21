#!/usr/bin/env python3
"""Validate completed runs, aggregate matched requests, and anonymize quality review."""
import argparse, hashlib, json, random, statistics
from pathlib import Path
MODELS=['Q4_K_M','IQ4_XS','Q4_K_S','Q3_K_M']
def summarize(folder,corpus):
 cases=json.loads(corpus.read_text())['cases'];ids={c['id'] for c in cases};allrows={};summary={};corpus_sha=hashlib.sha256(corpus.read_bytes()).hexdigest();runtime_sha=set()
 for name in MODELS:
  rows=[json.loads(l) for l in (folder/(name+'.jsonl')).read_text().splitlines()]
  assert rows[-1]['type']=='completed',name
  meta=rows[0];assert meta['corpus_sha256']==corpus_sha
  runtime_sha.add(meta['library_sha256']);data=[x for x in rows if x['type']=='result' and not x['warmup']]
  assert len(data)==len(ids)*2 and all(x['code']==0 and x['output'].strip() for x in data)
  for n in [1,2]:assert {x['id'] for x in data if x['pass_number']==n}==ids
  loaded=next(x for x in rows if x['type']=='loaded')
  bycase={i:[x for x in data if x['id']==i] for i in ids}
  allrows[name]=bycase
  summary[name]={'model_bytes':meta['model_bytes'],'model_sha256':meta['model_sha256'],'load_seconds':loaded['seconds'],'corpus_seconds_per_pass':[sum(x['seconds'] for x in data if x['pass_number']==n) for n in [1,2]],'ordinary29_seconds_per_pass':[sum(x['seconds'] for x in data if x['pass_number']==n and x['id']!='mtp-synthetic_long_ru') for n in [1,2]],'repetition_stress_seconds_per_pass':[next(x['seconds'] for x in data if x['pass_number']==n and x['id']=='mtp-synthetic_long_ru') for n in [1,2]],'median_request_seconds':statistics.median(x['seconds'] for x in data),'median_first_token_seconds':statistics.median(x['first_token_seconds'] for x in data),'loaded_memory':loaded['memory'],'sampled_peak':{k:max(x['memory_peak'][k] for x in data) for k in data[0]['memory_peak']},'unstable_cases':[i for i,x in bycase.items() if x[0]['output']!=x[1]['output']],'system_before':meta['system'],'system_after':rows[-1]['system']}
 assert len(runtime_sha)==1
 blind=[];mapping={}
 for case in cases:
  names=MODELS[:];random.Random('index-quant-'+case['id']).shuffle(names)
  choices=[];mapping[case['id']]={}
  for letter,name in zip('ABCD',names):
   outputs=list(dict.fromkeys(x['output'] for x in allrows[name][case['id']]))
   choices.append({'label':letter,'translations':outputs});mapping[case['id']][letter]=name
  blind.append({'id':case['id'],'source':case['text'],'target':case['target'],'choices':choices})
 (folder/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
 (folder/'blind-review.json').write_text(json.dumps(blind,ensure_ascii=False,indent=2)+'\n')
 (folder/'blind-key.json').write_text(json.dumps(mapping,indent=2)+'\n')
 print('PASS: four completed runs, 240 measured requests, matching corpus/runtime hashes and valid outputs')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('--corpus',type=Path,default=Path(__file__).with_name('corpus.json'));a=p.parse_args();summarize(a.folder,a.corpus)
