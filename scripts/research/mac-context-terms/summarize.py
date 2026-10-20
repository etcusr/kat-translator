#!/usr/bin/env python3
"""Publish timing/hash evidence without copying private source or translations."""
import argparse
from pathlib import Path
import hashlib
import json
import statistics
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
r=json.loads(a.input.read_text());summary={k:r[k] for k in ['fixture_sha256','load_seconds','planner_parity']}
summary['modes']={}
for mode in ['plain','context','context_terms','terms']:
 rows=[row for row in r['results'] if row['mode']==mode and row['phase']=='warm']
 if not rows: continue
 hashes=[hashlib.sha256(row['output'].encode()).hexdigest() for row in rows]
 result=dict(runs=len(rows),identical_outputs=len(set(hashes))==1,output_sha256=hashes,
             block_characters=rows[0]['block_characters'],pieces_per_block=rows[0]['pieces_per_block'])
 for metric in ['seconds','first_body_part_seconds','first_token_seconds','first_body_token_seconds','first_part_seconds']:
  values=[row[metric] for row in rows]
  result[metric]=dict(median=statistics.median(values),minimum=min(values),maximum=max(values),runs=values)
 result['prompt_tokens']=[item['prompt_tokens'] for item in rows[0]['trace']]
 result['term_counts']={term:[row['output'].casefold().count(term) for row in rows] for term in ['long-range drones','long-range aircraft','missiles','offensive','drone attack']}
 # Digits are compared separately from terminology; this is not a semantic score.
 result['figures_preserved']=[all(value in row['output'].replace(',','') for value in ['1015','16','250','300']) for row in rows]
 summary['modes'][mode]=result
assert len(summary['modes'])==4
summary['scope']='Single private RU→EN image; hand-prepared glossary; model load and full first pass excluded from warm medians; no OCR/UI/TTS latency claim.'
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(summary,indent=2)+'\n')
for mode,result in summary['modes'].items(): print(mode,round(result['first_body_part_seconds']['median'],3),round(result['seconds']['median'],3),result['identical_outputs'])
