#!/usr/bin/env python3
"""Paired, same-text chunk comparison; quality requires source/output review."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import statistics


def summarize(data):
    grouped=collections.defaultdict(list)
    for row in data['results']:grouped[(row['id'],row['mode'])].append(row)
    cases=[]
    for case in data['cases']:
        modes={}
        for mode in ['whole','chunk_plain','chunk_context']:
            rows=grouped[case['id'],mode]
            assert sorted(r['repeat'] for r in rows)==list(range(data['repeats'])),(case['id'],mode)
            success=[r for r in rows if r['code']==0]
            for row in success:
                for event in row['progress_events']:
                    assert row['output'].startswith(event['output']),(case['id'],mode,'progress mismatch')
                if mode!='whole':
                    assert all(c['code']==0 and c['input_tokens']<=1024 for c in row['chunks'])
                    assert row['chunks'][0]['start']==0
                    assert row['chunks'][-1]['end']==len(case['text'])
                    assert all(a['end']==b['start'] for a,b in zip(row['chunks'],row['chunks'][1:]))
                    assert len(row['progress_events'])==len(row['chunks'])
            modes[mode]=dict(codes=[r['code'] for r in rows],successes=len(success),
                identical_outputs=len({r['output'] for r in rows})==1,
                median_e2e=statistics.median(r['end_to_end_seconds'] for r in success) if success else None,
                median_first_visible=statistics.median(r['first_visible_seconds'] for r in success) if success else None,
                e2e=[r['end_to_end_seconds'] for r in rows],parts=[len(r.get('chunks',[])) for r in rows],
                numeric_repetition=[dict(time_0925=r['output'].count('09:25'),time_1125=r['output'].count('11:25')) for r in rows] if case['kind']=='boundary' else None)
        cases.append(dict(id=case['id'],kind=case['kind'],words=case['words'],modes=modes))
    return dict(requests=len(data['results']),repeats=data['repeats'],cases=cases,
        successes={m:sum(r['code']==0 for r in data['results'] if r['mode']==m) for m in ['whole','chunk_plain','chunk_context']},
        no_reload=all(r['model_reused'] and r['load_seconds']==0 for r in data['results']),
        worker_exit_code=data['worker_exit_code'])


def compact(data):
    # Keep full final and per-chunk text; replace cumulative progress copies by hashes.
    for row in data['results']:
        for event in row['progress_events']:
            output=event.pop('output')
            event['output_sha256']=hashlib.sha256(output.encode()).hexdigest()
            event['output_characters']=len(output)
    return data


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('input',type=Path);parser.add_argument('directory',type=Path)
    args=parser.parse_args();data=json.loads(args.input.read_text());summary=summarize(data)
    args.directory.mkdir(parents=True,exist_ok=True)
    (args.directory/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    (args.directory/'results.json').write_text(json.dumps(compact(data),ensure_ascii=False,indent=2)+'\n')
