"""Local CPU screening of additional official/author RU/EN translation weights."""
import argparse,json,time,hashlib,platform,importlib.metadata
from pathlib import Path
from huggingface_hub import HfApi,snapshot_download
P=argparse.ArgumentParser();P.add_argument('action',choices=['prepare','run']);P.add_argument('--candidate',choices=['wmt19','t5large'],required=True);a=P.parse_args()
root=Path(__file__).resolve().parents[2];cache=root/'.build/pair-mt/alternatives';out=root/'docs/benchmarks/pair-mt-ru-en';manifest_path=out/(a.candidate+'-manifest.json')
repos=['facebook/wmt19-ru-en','facebook/wmt19-en-ru'] if a.candidate=='wmt19' else ['utrobinmv/t5_translate_en_ru_zh_large_1024']
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(4194304):h.update(b)
 return h.hexdigest()
if a.action=='prepare':
 meta={}
 for repo in repos:
  info=HfApi().model_info(repo,token=False);filenames=[x.rfilename for x in info.siblings];weight='model.safetensors' if 'model.safetensors' in filenames else 'pytorch_model.bin'
  path=cache/repo.split('/')[-1]
  snapshot_download(repo,revision=info.sha,token=False,local_dir=path,allow_patterns=[weight,'*.json','*.txt','*.spm','*.model','README.md'])
  meta[repo]=dict(revision=info.sha,files=[dict(path=f.name,bytes=f.stat().st_size,sha256=sha(f)) for f in sorted(path.iterdir()) if f.is_file()]);manifest_path.write_text(json.dumps(meta,indent=2)+'\n');print(repo,'prepared',flush=True)
else:
 import torch
 from transformers import FSMTForConditionalGeneration,FSMTTokenizer,T5ForConditionalGeneration,T5Tokenizer
 torch.set_num_threads(4);rows=json.loads((out/'corpus.json').read_text());meta={'platform':platform.platform(),'torch':torch.__version__,'transformers':importlib.metadata.version('transformers'),'device':'cpu','threads':4,'num_beams':5,'corpus_sha256':sha(out/'corpus.json'),'manifest_sha256':sha(manifest_path),'note':'Original weights loaded FP32; no input truncation, output cap512; no iPhone speed claim.'}
 with (out/(a.candidate+'-results.jsonl')).open('x') as f:
  for repo in repos:
   path=cache/repo.split('/')[-1]
   is_t5=a.candidate=='t5large';tok=(T5Tokenizer if is_t5 else FSMTTokenizer).from_pretrained(path,local_files_only=True);model=(T5ForConditionalGeneration if is_t5 else FSMTForConditionalGeneration).from_pretrained(path,local_files_only=True).eval()
   for row in rows:
    if not is_t5 and not repo.endswith(row['source']+'-'+row['target']):continue
    text=('translate to '+row['target']+': ' if is_t5 else '')+row['text'];inputs=tok(text,return_tensors='pt');assert inputs.input_ids.shape[1]<=1024
    start=time.monotonic()
    with torch.inference_mode():result=model.generate(**inputs,num_beams=5,max_new_tokens=512,do_sample=False)
    answer=dict(id=row['id'],repo=repo,text=tok.decode(result[0],skip_special_tokens=True),seconds=time.monotonic()-start,input_tokens=inputs.input_ids.shape[1],output_tokens=result.shape[1],hit_output_cap=result.shape[1]>=512)
    f.write(json.dumps(answer,ensure_ascii=False)+'\n');f.flush();print(row['id'],answer['text'],flush=True)
   del model
 (out/(a.candidate+'-run-metadata.json')).write_text(json.dumps(meta,indent=2)+'\n')
