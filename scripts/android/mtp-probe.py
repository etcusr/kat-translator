#!/usr/bin/env python3
"""One isolated Index server experiment. Invoke through thermal_control.py.

Uses the existing on-device GGUF, no draft model download and no app changes.
Raw server logs and response JSON retain draft/acceptance statistics.
"""
import argparse
import http.client
import json
import os
import re
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request

MODEL = '/sdcard/Android/data/org.openoffline.translator.android/files/Index-Translate-9B.Q4_K_M.gguf'
PROMPT = ('<|im_start|>user\n请将以下文本翻译为英语，直接输出翻译结果，不要进行任何解释。\n\n'
          'Привет! Встреча завтра в 15:30.'
          '<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n')
REFERENCE_TOKENS = [9419, 0, 561, 6236, 369, 16089, 506, 220, 16, 20, 25, 18, 15, 13, 248046]
FIXTURE_PATH=Path(__file__).resolve().parents[2]/'tests/fixtures/android/index-gpu-corpus.json'
FIXTURES={case['id']:case for case in json.loads(FIXTURE_PATH.read_text())['cases']}
PROMPT_COUNTS={'short-ru-en':36,'numbers-ru-en':61,'medium-en-ru':82,'long-ru-en':147,'changed-text-ru-en':49}
# Reuse the existing Apple MTP benchmark text for a matched-input comparison.
APPLE_FIXTURE_PATH=Path(__file__).resolve().parents[2]/'tests/fixtures/index-mtp-cases.json'
APPLE_EN01=next(case for case in json.loads(APPLE_FIXTURE_PATH.read_text()) if case['id']=='en01')
FIXTURES['iphone-en01']={'id':'iphone-en01','text':APPLE_EN01['text'],
                       'target':APPLE_EN01['to_language'],
                       'patterns':['Бенну','не обнаружили','дезоксирибоз']}
PROMPT_COUNTS['iphone-en01']=49


def validate_response(result, case=None):
    if case is None and result.get('content', '').strip() != 'Hello! The meeting is tomorrow at 15:30.':
        raise AssertionError('Translation differs from the fixed baseline')
    if case is None and result.get('tokens') != REFERENCE_TOKENS:
        raise AssertionError('Token stream differs from greedy baseline, including EOS')
    timings = result.get('timings', {})
    expected_prompt=46 if case is None else PROMPT_COUNTS[case['id']]
    if timings.get('cache_n') != 0 or timings.get('prompt_n') != expected_prompt:
        raise AssertionError('Prompt was cached or differs from the app prompt')
    if result.get('truncated') is not False:
        raise AssertionError('Generation did not finish normally')
    if case is not None:
        if not result.get('tokens') or result['tokens'][-1]!=REFERENCE_TOKENS[-1]:
            raise AssertionError('Missing EOS')
        for pattern in case['patterns']:
            if not re.search(pattern,result.get('content',''),re.I):
                raise AssertionError('Missing translation fact: '+pattern)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', default=os.environ.get('ANDROID_SERIAL'), required=not os.environ.get('ANDROID_SERIAL'))
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--draft', type=int, choices=[0, 1, 2, 3], required=True, help='0 disables MTP')
    parser.add_argument('--repeats', type=int, choices=range(1, 6), default=1)
    parser.add_argument('--profile-stages', action='store_true', help='Adds GPU fences; diagnostic timing only')
    parser.add_argument('--mmq-tile', choices=['stock','medium','compact','lean','index','q6wide'], default='stock')
    parser.add_argument('--q6-direct', action='store_true', help='Diagnostic Q6 coefficient loads without shared-memory barriers')
    parser.add_argument('--draft-sampling', choices=['gpu','cpu'], default='gpu')
    parser.add_argument('--multi-matvec', action='store_true')
    parser.add_argument('--flash', choices=['on', 'off'], default='on',
                        help='Controlled Flash Attention comparison; weights and KV precision unchanged')
    parser.add_argument('--checkpoints', type=int, choices=[0,8], default=0,
                        help='0 avoids server prompt-cache checkpoints; app does not use them')
    parser.add_argument('--case',choices=list(FIXTURES),help='Optional existing regression fixture')
    args = parser.parse_args()
    # Automatic thermal retries receive distinct directories, never overwrite evidence.
    args.out.mkdir(parents=True, exist_ok=True)
    import tempfile
    output = Path(tempfile.mkdtemp(prefix=f'draft-{args.draft}-', dir=args.out))
    adb = ['adb', '-s', args.serial]
    def remote(*command, **kwargs):
        return subprocess.run(adb + list(command), check=True, timeout=20, **kwargs)
    # ADB allocates a free local port; the server is only reachable through USB/loopback.
    local_port = remote('forward', 'tcp:0', 'tcp:18891', capture_output=True, text=True).stdout.strip()
    url = f'http://127.0.0.1:{int(local_port)}'
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    server = None
    with (output / 'server.log').open('w') as log:
        try:
            environment=[]
            if args.profile_stages: environment+=['KAT_MTP_PROFILE=1']
            if args.mmq_tile!='stock': environment+=['KAT_VK_MALI_MMQ_TILE='+args.mmq_tile]
            else: environment+=['KAT_VK_STOCK_G715_PREFILL=1']
            if args.multi_matvec: environment+=['KAT_VK_MALI_MMV_MULTI=1']
            if args.q6_direct: environment+=['KAT_VK_Q6_DIRECT=1']
            command = adb + ['shell', 'env'] + environment + ['/data/local/tmp/kat_mtp_probe', '-m', MODEL,
                             '-c', '2048', '-b', '512', '-ub', '128', '-t', '4', '-tb', '4',
                             '-ngl', '99', '-dev', 'Vulkan0', '-fa', args.flash, '-np', '1', '--host', '127.0.0.1',
                             '--port', '18891', '--no-webui', '--no-warmup', '--no-cache-prompt',
                             '--ctx-checkpoints', str(args.checkpoints),
                             '--metrics', '--spec-type', 'draft-mtp' if args.draft else 'none']
            if args.draft:
                command += ['--spec-draft-n-max', str(args.draft), '--spec-draft-n-min', '1']
                if args.draft_sampling=='cpu': command+=['--no-spec-draft-backend-sampling']
            (output / 'command.json').write_text(json.dumps(command, indent=2))
            server = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 180
            while True:
                if server.poll() is not None:
                    raise RuntimeError(f'Server exited {server.returncode}; inspect {output}/server.log')
                try:
                    with opener.open(url + '/health', timeout=2) as response:
                        if response.status == 200:
                            break
                except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.HTTPException):
                    pass
                if time.monotonic() >= deadline:
                    raise TimeoutError('Server startup exceeded 180 seconds')
                time.sleep(1)
            case=FIXTURES[args.case] if args.case else None
            prompt=PROMPT
            if case is not None:
                target={'en':'英语','ru':'俄语'}[case['target']]
                prompt=f"<|im_start|>user\n请将以下文本翻译为{target}，直接输出翻译结果，不要进行任何解释。\n\n"+case['text']+'<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n'
            request = {'prompt': prompt, 'temperature': 0, 'seed': 1, 'n_predict': 256 if case else 64,
                       'cache_prompt': False, 'stream': False, 'return_tokens': True}
            (output / 'request.json').write_text(json.dumps(request, ensure_ascii=False, indent=2))
            for index in range(args.repeats):
                started = time.monotonic()
                with opener.open(urllib.request.Request(url + '/completion', json.dumps(request).encode(),
                               {'Content-Type': 'application/json'}), timeout=180) as response:
                    result = json.load(response)
                result['probeWallSeconds'] = time.monotonic() - started
                (output / f'response-{index}.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
                print(json.dumps({'output': str(output), 'draft': args.draft, 'repeat': index,
                                  'text': result.get('content'), 'timings': result.get('timings'),
                                  'wallSeconds': result['probeWallSeconds']}, ensure_ascii=False), flush=True)
                validate_response(result,case)
            with opener.open(url + '/metrics', timeout=10) as response:
                (output / 'metrics.txt').write_bytes(response.read())
        finally:
            # This unique process name is reserved for this diagnostic executable.
            subprocess.run(adb + ['shell', 'pkill', '-x', 'kat_mtp_probe'], timeout=20, check=False)
            if server is not None:
                try:
                    server.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()
            remote('forward', '--remove', f'tcp:{local_port}')


if __name__ == '__main__':
    main()
