#!/usr/bin/env python3
"""Opt-in engine smoke test of packaged Store Python; no app install or downloads.

The inherited-sandbox helper cannot be launched from an ordinary shell. A temporary
copy loses only its signing entitlements; all libraries, modules and model files
are read from the supplied app/model directories. This is not sandbox/UI acceptance.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--models', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
contents = args.app.resolve() / 'Contents'
resources = contents / 'Resources'
models = args.models.resolve()
checks = {
    'wayu': (['WayuPython'], '''
import importlib.util, hashlib, wayu_frontend
assert importlib.util.find_spec('_ssl') is None
assert importlib.util.find_spec('_hashlib') is None
assert len(hashlib.sha256(b'kat').digest()) == 32
tokens = wayu_frontend.tokens('สวัสดีครับ')
assert len(tokens) > 2
result = dict(tokens=len(tokens), tlsExtension=False)
'''),
    'index': (['IndexPython', 'WayuPython'], '''
from index_mlx import Engine
engine = Engine(str(models / 'index-translate-9b-mlx-mtp2'))
prefix = '<|im_start|>user\\n请将以下文本翻译为英语，直接输出翻译结果，不要进行任何解释。\\n\\n'
suffix = '<|im_end|>\\n<|im_start|>assistant\\n<think>\\n\\n</think>\\n\\n'
partials = []
code, text, first = engine.run(prefix, 'Я хотел бы забронировать номер в отеле.', suffix, lambda: False, partials.append)
assert code == 0 and text and 'hotel' in text.lower(), (code, text)
assert partials and partials[-1] == text
engine.close()
result = dict(text=text, firstTokenSeconds=first, partials=len(partials), mtp=2)
'''),
    'opus': (['OpusPython'], '''
from opus_gpu import Engine
engine = Engine(str(models / 'opus-mt-big-gpu-fp16'))
outputs = []
for source, target, text, expected in [
    ('ru', 'en', 'Я хотел бы забронировать номер в отеле.', 'hotel'),
    ('en', 'ru', 'I would like to book a hotel room.', 'номер')]:
    value = engine.run(dict(source=source, target=target, text=text))
    assert value['code'] == 0 and expected in value['text'].lower(), value
    assert value['device'] == 'mps:0' and value['precision'] == 'float16'
    outputs.append(value)
result = dict(outputs=outputs)
'''),
}
results = {}
with tempfile.TemporaryDirectory(prefix='kat-store-runtime-') as directory:
    root = Path(directory)
    (root / 'MacOS').mkdir()
    (root / 'Frameworks').symlink_to(contents / 'Frameworks', target_is_directory=True)
    helper = root / 'MacOS/OpusPython'
    shutil.copy2(contents / 'MacOS/OpusPython', helper)
    subprocess.run(['codesign', '--force', '--sign', '-', str(helper)], check=True, capture_output=True)
    for name, (paths, body) in checks.items():
        env = dict(os.environ, PYTHONHOME=str(resources / 'python'),
                   PYTHONPATH=os.pathsep.join(str(resources / path) for path in paths),
                   PYTHONNOUSERSITE='1', PYTHONDONTWRITEBYTECODE='1',
                   HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1')
        code = ('import json, sys, time\nfrom pathlib import Path\n'
                'models=Path(sys.argv[1]); start=time.perf_counter()\n' + body +
                '\nresult["secondsIncludingLoad"]=time.perf_counter()-start\n'
                'print("KAT_RESULT="+json.dumps(result, ensure_ascii=False))\n')
        run = subprocess.run([str(helper), '-S', '-B', '-c', code, str(models)],
                             env=env, capture_output=True, text=True, timeout=180)
        if run.returncode:
            raise RuntimeError(f'{name}: {run.returncode}\n{run.stdout}\n{run.stderr}')
        lines = [line.removeprefix('KAT_RESULT=') for line in run.stdout.splitlines()
                 if line.startswith('KAT_RESULT=')]
        results[name] = json.loads(lines[-1])
        print(name + ': passed', flush=True)
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(dict(scope='engine-only; temporary helper signature, archive unchanged',
                                     results=results), ensure_ascii=False, indent=2) + '\n')
