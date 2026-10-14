#!/usr/bin/env python3
"""Fetch pinned OmniVoice Q8 files with source LFS SHA256 validation."""
import hashlib,json,pathlib,shutil,urllib.request
R=pathlib.Path(__file__).resolve().parents[1];O=R/'model-store/downloads/omnivoice';O.mkdir(exist_ok=True)
REV='017094167b5c9ed565a5076ac9b3b93c5ecf5c73'
base='https://huggingface.co/Serveurperso/OmniVoice-GGUF'
with urllib.request.urlopen('https://huggingface.co/api/models/Serveurperso/OmniVoice-GGUF/tree/'+REV+'?expand=true',timeout=60) as r:tree=json.load(r)
files=[]
for name,id in [('omnivoice-base-Q8_0.gguf','omnivoice-q8-base'),('omnivoice-tokenizer-Q8_0.gguf','omnivoice-q8-codec')]:
 meta=next(x for x in tree if x['path']==name);path=O/name;url=base+'/resolve/'+REV+'/'+name
 if not path.exists():
  with urllib.request.urlopen(url,timeout=120) as r,path.with_suffix('.partial').open('wb') as f:shutil.copyfileobj(r,f,1024*1024)
  path.with_suffix('.partial').replace(path)
 with path.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
 assert path.stat().st_size==meta['size'] and digest==meta['lfs']['oid']
 files.append(dict(id=id,path=name,remoteURL=url,byteCount=path.stat().st_size,sha256=digest))
 print(name,path.stat().st_size,'verified',flush=True)
(R/'docs/research/omnivoice-2026-10-07/assets.json').write_text(json.dumps(files,indent=2)+'\n')
