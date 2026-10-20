#!/usr/bin/env python3
"""Synthetic long/context probe through the actual resident Mac Lab worker."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import select
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--repeats', type=int, default=3)
    args = parser.parse_args()
    if args.repeats < 2:
        parser.error('Use at least two repeats for stability')
    fixture = ROOT/'tests/fixtures/mac-long-context.json'
    cases = json.loads(fixture.read_text())
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['TRANSFORMERS_OFFLINE'] = '1'
    from transformers import AutoTokenizer
    from kat_runner import SUFFIX
    model = Path.home()/'Library/Application Support/OfflineTranslator/TranslationPackages/index-translate-9b-mlx-mtp2'
    tokenizer = AutoTokenizer.from_pretrained(str(model), local_files_only=True)
    def count(text, target):
        lang = {'ru':'俄语','en':'英语'}[target]
        prompt = f'<|im_start|>user\n请将以下文本翻译为{lang}，直接输出翻译结果，不要进行任何解释。\n\n'
        return len(tokenizer.encode(prompt+text+SUFFIX, add_special_tokens=False))
    # Boundary cases are repetitive by design, not natural-language quality cases.
    sentence = 'The train leaves at 09:25, not 11:25. Do not cancel the return ticket. '
    for case_id, threshold in [('en-output-budget',1400),('en-input-limit',1550)]:
        text = sentence
        while count(text, 'ru') < threshold:
            text += sentence
        cases.append(dict(id=case_id,source='en',target='ru',kind='boundary',text=text,
                          meaning_checks=['Explicit failure is preferable to silent partial translation']))
    metadata = [{**case,'words':len(case['text'].split()),
                 'input_tokens':count(case['text'],case['target'])} for case in cases]
    runner = Path(__file__).with_name('kat_runner.py')
    python = ROOT/'.build/mac-index-mlx-mtp/venv/bin/python'
    report = dict(fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                  runner_sha256=hashlib.sha256(runner.read_bytes()).hexdigest(),
                  harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  repeats=args.repeats, cases=metadata, results=[])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    log_path = args.output.with_suffix('.stderr.log')
    with log_path.open('w') as errors:
        worker = subprocess.Popen([str(python),str(runner),'index9b','--serve'],
                                  stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errors,text=True)
        def request(case):
            started=time.perf_counter()
            worker.stdin.write(json.dumps(case,ensure_ascii=False)+'\n');worker.stdin.flush()
            if not select.select([worker.stdout],[],[],120)[0]:
                raise TimeoutError('Worker response exceeded 120 seconds')
            line=worker.stdout.readline()
            if not line:raise RuntimeError('Worker exited without response')
            result=json.loads(line)
            result['end_to_end_seconds']=time.perf_counter()-started
            result['output_tokens']=len(tokenizer.encode(result.get('output',''),add_special_tokens=False))
            return result
        try:
            report['startup']=request(dict(id='startup',source='en',target='ru',kind='warmup',text='Please keep the return ticket.'))
            save()
            for repeat in range(args.repeats):
                order=list(metadata)
                random.Random(20261020+repeat).shuffle(order)
                for case in order:
                    row=request(case)
                    row['repeat']=repeat
                    report['results'].append(row);save()
                    print(repeat,case['id'],f"{row['seconds']:.3f}s",'code',row['code'],flush=True)
            worker.stdin.close();worker.wait(timeout=20)
            report['worker_exit_code']=worker.returncode
            save()
        finally:
            if worker.poll() is None:worker.terminate();worker.wait(timeout=20)
            if not worker.stdin.closed:worker.stdin.close()
            worker.stdout.close()


if __name__=='__main__':main()
