import json,hashlib
from pathlib import Path
from huggingface_hub import HfApi,hf_hub_download
repo='bartowski/microsoft_Phi-4-mini-instruct-GGUF'
name='microsoft_Phi-4-mini-instruct-Q4_K_M.gguf'
info=HfApi().model_info(repo,files_metadata=True,token=False)
f=next(f for f in info.siblings if f.rfilename==name)
meta={'repo':repo,'revision':info.sha,'filename':name,'bytes':f.size,'expected_sha256':f.lfs.sha256,'source_model':'microsoft/Phi-4-mini-instruct','quantization':'Q4_K_M; community conversion'}
out=Path('docs/benchmarks/pair-mt-ru-en/phi4-mini/download.json');out.write_text(json.dumps(meta,indent=2)+'\n');print(meta,flush=True)
p=Path(hf_hub_download(repo,name,revision=info.sha,local_dir='model-store/downloads',token=False))
h=hashlib.sha256()
with p.open('rb') as r:
 while b:=r.read(4194304):h.update(b)
assert h.hexdigest()==meta['expected_sha256']
meta['verified_sha256']=h.hexdigest();out.write_text(json.dumps(meta,indent=2)+'\n');print('Verified',p,flush=True)
for file in ['tokenizer_config.json','config.json']:
 hf_hub_download('microsoft/Phi-4-mini-instruct',file,local_dir='.build/phi4-mini/tokenizer',token=False)
