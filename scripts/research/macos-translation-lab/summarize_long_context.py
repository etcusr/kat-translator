#!/usr/bin/env python3
"""Summarize resident latency by case and length; no automatic quality score."""
import argparse
import collections
import json
import math
from pathlib import Path
import statistics


def stats(values):
    ordered=sorted(values)
    return dict(n=len(values),minimum=min(values),median=statistics.median(values),
                maximum=max(values),p95_nearest_rank=ordered[math.ceil(.95*len(ordered))-1])


def summarize(data):
    grouped=collections.defaultdict(list)
    for row in data['results']:
        grouped[row['id']].append(row)
    cases=[]
    for case in data['cases']:
        rows=grouped[case['id']]
        assert len(rows)==data['repeats'],case['id']
        assert sorted(r['repeat'] for r in rows)==list(range(data['repeats']))
        valid=[r for r in rows if r['code']==0]
        timing=stats([r['seconds'] for r in valid]) if valid else None
        cases.append(dict(id=case['id'],kind=case['kind'],source=case['source'],
            words=case['words'],input_tokens=case['input_tokens'],successful=len(valid),
            codes=[r['code'] for r in rows],identical_outputs=len({r['output'] for r in rows})==1,
            seconds=[r['seconds'] for r in rows],latency=timing,
            max_min_ratio=timing['maximum']/timing['minimum'] if timing else None,
            ttft=stats([r['first_token_seconds'] for r in valid]) if valid else None,
            end_to_end=stats([r['end_to_end_seconds'] for r in rows]),
            output_tokens=[r['output_tokens'] for r in rows]))
    groups={}
    for kind in sorted({c['kind'] for c in cases}):
        rows=[r for r in data['results'] if r['kind']==kind]
        valid=[r for r in rows if r['code']==0]
        groups[kind]=dict(requests=len(rows),successful=len(valid),
            latency=stats([r['seconds'] for r in valid]) if valid else None,
            ttft=stats([r['first_token_seconds'] for r in valid]) if valid else None)
    return dict(startup=data['startup'],cases=cases,groups=groups,
        total_requests=len(data['results']),successful=sum(r['code']==0 for r in data['results']),
        no_reload=all(r['model_reused'] and r['load_seconds']==0 for r in data['results']),
        worker_exit_code=data['worker_exit_code'],
        quality_assessment='See manual review against predeclared meaning checks; timing and identity are not quality scores.')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('input',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args()
    args.output.write_text(json.dumps(summarize(json.loads(args.input.read_text())),ensure_ascii=False,indent=2)+'\n')
