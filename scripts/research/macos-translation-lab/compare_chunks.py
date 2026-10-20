#!/usr/bin/env python3
"""Same resident worker, matched inputs; whole/plain chunks/context chunks."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import select
import subprocess
import time

ROOT=Path(__file__).resolve().parents[3]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path)
    parser.add_argument('--repeats',type=int,default=2);parser.add_argument('--ids')
    parser.add_argument('--fixtures',type=Path)
    args=parser.parse_args()
    prior=args.fixtures or ROOT/'docs/benchmarks/mac-long-context-2026-10-20/results.json'
    source=json.loads(prior.read_text())
    cases=source['cases'] if isinstance(source,dict) else source
    if args.ids:cases=[c for c in cases if c['id'] in args.ids.split(',')]
    if not cases or args.repeats<1:parser.error('No cases or invalid repeat count')
    runner=Path(__file__).with_name('kat_runner.py');splitter=Path(__file__).with_name('chunking.py')
    report=dict(cases=cases,repeats=args.repeats,source_corpus_sha256=hashlib.sha256(prior.read_bytes()).hexdigest(),
        runner_sha256=hashlib.sha256(runner.read_bytes()).hexdigest(),chunker_sha256=hashlib.sha256(splitter.read_bytes()).hexdigest(),results=[])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    def save():args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    with args.output.with_suffix('.stderr.log').open('w') as log:
        worker=subprocess.Popen([str(ROOT/'.build/mac-index-mlx-mtp/venv/bin/python'),str(runner),'index9b','--serve'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log)
        pending=b''
        def line(timeout=120):
            nonlocal pending
            deadline=time.monotonic()+timeout
            while b'\n' not in pending:
                remaining=deadline-time.monotonic()
                if remaining<=0 or not select.select([worker.stdout],[],[],remaining)[0]:raise TimeoutError('Worker stalled')
                block=worker.stdout.read1(65536)
                if not block:raise RuntimeError('Worker exited')
                pending+=block
            result,pending=pending.split(b'\n',1)
            return json.loads(result)
        def request(case,mode):
            started=time.perf_counter();first_visible=None;events=[]
            worker.stdin.write((json.dumps({**case,'mode':mode,'progress':True},ensure_ascii=False)+'\n').encode());worker.stdin.flush()
            while True:
                row=line()
                if row.get('event')=='progress':
                    elapsed=time.perf_counter()-started
                    if first_visible is None:first_visible=elapsed
                    events.append(dict(completed=row['completed'],total=row['total'],elapsed=elapsed,output=row['output']))
                    continue
                row['end_to_end_seconds']=time.perf_counter()-started
                row['first_visible_seconds']=first_visible if first_visible is not None else (row['end_to_end_seconds'] if row.get('code')==0 else None)
                row['progress_events']=events
                for key in ('text','meaning_checks'):row.pop(key,None)
                return row
        try:
            report['startup']=request(dict(id='startup',source='en',target='ru',text='Please keep the return ticket.'),'whole');save()
            for repeat in range(args.repeats):
                order=[(c,m) for c in cases for m in ('whole','chunk_plain','chunk_context')]
                random.Random(260120+repeat).shuffle(order)
                for case,mode in order:
                    row=request(case,mode);row['repeat']=repeat
                    if 'code' not in row:raise RuntimeError(row)
                    report['results'].append(row);save()
                    print(repeat,case['id'],mode,f"{row['seconds']:.2f}s",'code',row['code'],'parts',len(row.get('chunks',[])),flush=True)
            worker.stdin.close();worker.wait(timeout=20);report['worker_exit_code']=worker.returncode;save()
        finally:
            if worker.poll() is None:worker.terminate();worker.wait(timeout=20)
            if not worker.stdin.closed:worker.stdin.close()
            worker.stdout.close()

if __name__=='__main__':main()
