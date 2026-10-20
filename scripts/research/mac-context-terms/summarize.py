#!/usr/bin/env python3
"""Publish timing/hash evidence without copying private source or translations."""
import argparse
from pathlib import Path
import hashlib
import json
import statistics
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path)
p.add_argument('--modes',default='plain,context,context_terms,terms');a=p.parse_args()
modes=a.modes.split(',')
r=json.loads(a.input.read_text());summary={k:r[k] for k in ['fixture_sha256','load_seconds','planner_parity']}
summary['modes']={}
for mode in modes:
 rows=[row for row in r['results'] if row['mode']==mode and row['phase']=='warm']
 if not rows: continue
 hashes=[hashlib.sha256(row['output'].encode()).hexdigest() for row in rows]
 result=dict(runs=len(rows),identical_outputs=len(set(hashes))==1,output_sha256=hashes,
             block_characters=rows[0]['block_characters'],pieces_per_block=rows[0]['pieces_per_block'])
 for metric in ['seconds','first_body_part_seconds','first_token_seconds','first_body_token_seconds','first_part_seconds','glossary_seconds']:
  values=[row.get(metric,0) for row in rows]
  result[metric]=dict(median=statistics.median(values),minimum=min(values),maximum=max(values),runs=values)
 if mode=='auto_terms':
  glossaries=[row['glossary'] for row in rows]
  result['glossary_entries']=[len(item['terms']) for item in glossaries]
  result['rejected_entries']=[item['rejected_entries'] for item in glossaries]
  result['glossary_prompt_tokens']=[item['prompt_tokens'] for item in glossaries]
  result['identical_glossaries']=len({json.dumps(item['terms'],sort_keys=True) for item in glossaries})==1
 result['prompt_tokens']=[item['prompt_tokens'] for item in rows[0]['trace']]
 result['term_counts']={term:[row['output'].casefold().count(term) for row in rows] for term in ['long-range drones','long-range aircraft','missiles','offensive','drone attack']}
 # Digits are compared separately from terminology; this is not a semantic score.
 result['figures_preserved']=[all(value in row['output'].replace(',','') for value in ['1015','16','250','300']) for row in rows]
 summary['modes'][mode]=result
assert len(summary['modes'])==len(modes)
summary['scope']='Single private RU→EN image. Manual glossary preparation not timed. Automatic glossary regenerated from source for every request and included in total/first-part latency. Model load and full first pass excluded from warm medians; no OCR/UI/TTS latency claim.'
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(summary,indent=2)+'\n')
for mode,result in summary['modes'].items(): print(mode,round(result['first_body_part_seconds']['median'],3),round(result['seconds']['median'],3),result['identical_outputs'])
