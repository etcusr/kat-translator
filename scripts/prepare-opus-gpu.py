#!/usr/bin/env python3
"""Freeze the benchmarked offline Mac GPU worker, independently of Index Python."""
from pathlib import Path
import shutil,json,hashlib
root=Path(__file__).resolve().parents[1]
source=root/'.build/pair-mt-env/lib/python3.11/site-packages'
out=root/'Dependencies/build/opus-gpu/OpusPython';out.mkdir(parents=True,exist_ok=True)
names={'torch','torchgen','functorch','transformers','tokenizers','huggingface_hub','safetensors','numpy','numpy.libs','sentencepiece','sacremoses','regex','filelock','fsspec','packaging','yaml','pyyaml','six','requests','urllib3','charset_normalizer','idna','certifi','tqdm','sympy','mpmath','networkx','jinja2','markupsafe','typing_extensions','joblib','cloudpickle','click'}
for p in source.iterdir():
 stem=p.name.split('-')[0].removesuffix('.py').lower()
 if p.name not in names and stem not in names:continue
 target=out/p.name
 if p.is_dir():shutil.copytree(p,target,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
 else:shutil.copy2(p,target)
shutil.copy2(root/'shared/native/OpusGPU/opus_gpu.py',out/'opus_gpu.py')
files=[{'path':str(p.relative_to(out)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.rglob('*')) if p.is_file()]
(out.parent/'runtime-files.json').write_text(json.dumps(files,indent=2))
print('OPUS runtime',len(files),sum(x['bytes'] for x in files),'bytes')
