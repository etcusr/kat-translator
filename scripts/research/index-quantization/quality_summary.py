#!/usr/bin/env python3
"""Resolve completed source-based annotations only after blind review is finished."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('folder',type=Path);a=p.parse_args();w=a.folder
annotations=json.loads((w/'annotations.json').read_text());key=json.loads((w/'blind-key.json').read_text());assert len(annotations)==120
assert len({(x['id'],x['label']) for x in annotations})==120
rows=[dict(x,model=key[x['id']][x['label']]) for x in annotations]
models=['Q4_K_M','IQ4_XS','Q4_K_S','Q3_K_M'];summary={}
for m in models:
 r=[x for x in rows if x['model']==m];assert len(r)==30
 ordinary=[x for x in r if x['id']!='mtp-synthetic_long_ru'];assert len(ordinary)==29
 summary[m]={'ordinary_cases':29,'major_error_cases':[x['id'] for x in ordinary if any(z['severity']=='major' for z in x['issues'])],'minor_issue_cases':[x['id'] for x in ordinary if any(z['severity']=='minor' for z in x['issues'])],'repetition_stress':next(x for x in r if x['id']=='mtp-synthetic_long_ru')['issues']}
base={x['id']:x for x in rows if x['model']=='Q4_K_M'}
for m in models:
 r=[x for x in rows if x['model']==m and x['id']!='mtp-synthetic_long_ru']
 def major(x):return any(i['severity']=='major' for i in x['issues'])
 summary[m]['new_major_error_cases_vs_baseline']=[x['id'] for x in r if major(x) and not major(base[x['id']])]
 summary[m]['fixed_major_error_cases_vs_baseline']=[x['id'] for x in r if not major(x) and major(base[x['id']])]
out={'method':'Source-based single-assistant qualitative review; two blinded pairs, per-case shuffled labels; date/condition baseline smoke known. No independent expert validation. Artificial repetition stress reported separately.','models':summary,'annotations':rows}
(w/'quality.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False,indent=2))
