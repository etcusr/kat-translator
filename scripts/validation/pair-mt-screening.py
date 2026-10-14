"""Bounded RU/EN OPUS-MT quality screening, Mac CPU only; no iOS claims.
Prepare pins publisher snapshots and exports FP32 + INT8. Run is offline.
"""
import argparse, hashlib, json, platform, time, re, importlib.metadata
from pathlib import Path
P=argparse.ArgumentParser(description=__doc__);P.add_argument('action',choices=['prepare','run']);P.add_argument('--sentence-only',action='store_true');A=P.parse_args()
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/benchmarks/pair-mt-ru-en';CACHE=ROOT/'.build/pair-mt'
OUT.mkdir(parents=True,exist_ok=True);CACHE.mkdir(parents=True,exist_ok=True)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(4*1024*1024):h.update(b)
 return h.hexdigest()
def files(p):return [dict(path=str(f.relative_to(p)),bytes=f.stat().st_size,sha256=sha(f)) for f in sorted(p.rglob('*')) if f.is_file() and '.cache' not in f.parts]
if A.action=='prepare':
 from huggingface_hub import HfApi,snapshot_download
 import ctranslate2
 manifest={}
 for direction in ['ru-en','en-ru']:
  repo='Helsinki-NLP/opus-mt-'+direction
  rev=HfApi().model_info(repo,token=False).sha
  path=CACHE/direction/'original'
  snapshot_download(repo,revision=rev,token=False,local_dir=path,allow_patterns=['pytorch_model.bin','config.json','generation_config.json','tokenizer_config.json','source.spm','target.spm','vocab.json','README.md'])
  manifest[direction]=dict(repo=repo,revision=rev,original=files(path),exports={})
  for quant in ['float32','int8']:
   dest=CACHE/direction/quant
   if not dest.exists():ctranslate2.converters.TransformersConverter(str(path),copy_files=['source.spm','target.spm','vocab.json','tokenizer_config.json']).convert(str(dest),quantization=quant)
   manifest[direction]['exports'][quant]=files(dest)
  (OUT/'model-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
  print('prepared',direction,flush=True)
else:
 import ctranslate2
 from transformers import MarianTokenizer
 rows=json.loads((OUT/'corpus.json').read_text());assert len(rows)==26
 meta=dict(platform=platform.platform(),machine=platform.machine(),versions={p:importlib.metadata.version(p) for p in ['torch','transformers','ctranslate2','sentencepiece']},corpus_sha256=sha(OUT/'corpus.json'),manifest_sha256=sha(OUT/'model-manifest.json'),beam_size=4,threads=4,compute_types=sorted(ctranslate2.get_supported_compute_types('cpu')),note='Mac CPU, one warmup per loaded model; no iPhone speed/memory claim; no truncation; 512 input/output cap. Long paragraphs tested whole and sentencewise.')
 result_path=OUT/('opus-sentence-results.jsonl' if A.sentence_only else 'opus-results.jsonl')
 assert not result_path.exists(),'Choose fresh result file'
 with result_path.open('w') as f:
  for direction in ['ru-en','en-ru']:
   tok=MarianTokenizer.from_pretrained(CACHE/direction/'original',local_files_only=True)
   for quant in ['float32','int8']:
    start=time.monotonic();model=ctranslate2.Translator(str(CACHE/direction/quant),device='cpu',compute_type=quant,inter_threads=1,intra_threads=4);load=time.monotonic()-start
    def translate(text):
     ids=tok.encode(text);assert len(ids)<=512,(len(ids),text)
     start=time.monotonic();r=model.translate_batch([tok.convert_ids_to_tokens(ids)],beam_size=4,max_input_length=0,max_decoding_length=512)[0]
     return dict(text=tok.decode(tok.convert_tokens_to_ids(r.hypotheses[0]),skip_special_tokens=True),seconds=time.monotonic()-start,input_tokens=len(ids),output_tokens=len(r.hypotheses[0]))
    translate('Здравствуйте.' if direction=='ru-en' else 'Hello.')
    for row in rows:
     if row['source']!=direction[:2]:continue
     if A.sentence_only and (row['id'].endswith('-long') or len(re.split(r'(?<=[.!?])\s+',row['text']))<2):continue
     variants=['sentences'] if A.sentence_only else (['whole','sentences'] if row['id'].endswith('-long') else ['whole'])
     for variant in variants:
      chunks=[row['text']] if variant=='whole' else re.split(r'(?<=[.!?])\s+',row['text'])
      results=[translate(t) for t in chunks]
      result=dict(id=row['id'],direction=direction,quantization=quant,variant=variant,text=' '.join(r['text'] for r in results),seconds=sum(r['seconds'] for r in results),chunks=results,load_seconds=load,actual_compute_type=model.compute_type)
      assert all(r['output_tokens']<512 for r in results),'Output cap reached'
      f.write(json.dumps(result,ensure_ascii=False)+'\n');f.flush();print(direction,quant,row['id'],variant,result['text'],flush=True)
    del model
 (OUT/('sentence-run-metadata.json' if A.sentence_only else 'run-metadata.json')).write_text(json.dumps(meta,indent=2)+'\n')
