#!/usr/bin/env python3
"""Isolated same-runtime GGUF comparison; no app/container writes. JSONL is append-flushed.

Each model is a fresh process. Two independent requests per case, greedy decoding,
context reset by the frozen native wrapper. Sample physical footprint every 100 ms.
No automatic quality score: retain outputs for source-based review.
"""
import argparse, ctypes as c, hashlib, importlib.util, json, os, random, subprocess, threading, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('probe',ROOT/'scripts/research/context_translation_probe.py')
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)

def digest(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return h.hexdigest()

def main():
 p=argparse.ArgumentParser();p.add_argument('--model',type=Path,required=True);p.add_argument('--label',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--library',type=Path,required=True);p.add_argument('--metrics',type=Path,required=True);p.add_argument('--corpus',type=Path,default=Path(__file__).with_name('corpus.json'));p.add_argument('--repeats',type=int,default=2);p.add_argument('--only',nargs='*');a=p.parse_args()
 cases=json.loads(a.corpus.read_text())['cases'];cases=[x for x in cases if not a.only or x['id'] in a.only];assert cases
 lib=c.CDLL(str(a.metrics.resolve()));lib.kat_metrics.argtypes=[c.POINTER(c.c_double)];lib.kat_metrics.restype=c.c_int
 def metrics():
  v=(c.c_double*5)();assert lib.kat_metrics(v)==0
  return dict(zip(['footprint','resident','resident_process_peak','thermal','metal_allocated'],map(int,v)))
 def system():
  return {'swap':subprocess.check_output(['sysctl','vm.swapusage'],text=True).strip(),'thermal':metrics()['thermal']}
 a.output.parent.mkdir(parents=True,exist_ok=True)
 with a.output.open('x') as f:
  def save(d):f.write(json.dumps(d,ensure_ascii=False)+'\n');f.flush()
  save(dict(type='metadata',label=a.label,model_sha256=digest(a.model),model_bytes=a.model.stat().st_size,library_sha256=digest(a.library),corpus_sha256=digest(a.corpus),started=time.time(),system=system(),settings={'threads':4,'gpu_layers':99,'flash_attention':True,'greedy':True,'context':2048,'max_prompt':1536,'MTP':False,'context_reset_each_request':True,'memory_sample_seconds':0.1,'GGML_METAL_NO_RESIDENCY':os.environ.get('GGML_METAL_NO_RESIDENCY')}))
  engine=probe.Engine(a.library,a.model)
  save(dict(type='loaded',seconds=engine.load_seconds,memory=metrics(),system=system()))
  try:
   # Dedicated warmup is excluded from case timings; covers both target languages.
   warm=[dict(id='warm-ru-en',text='Спасибо за помощь. До встречи завтра.',target='en'),dict(id='warm-en-ru',text='Thank you for your help. See you tomorrow.',target='ru')]
   for rep in range(a.repeats+1):
    order=warm if rep==0 else list(cases)
    if rep:random.Random(2100+rep).shuffle(order)
    for item in order:
     # Pause on serious/critical thermal state; keep the wait out of latency.
     waited=0
     while metrics()['thermal']>=2 and waited<600:time.sleep(5);waited+=5
     if metrics()['thermal']>=2:raise RuntimeError('Thermal guard: serious after 10 min')
     samples=[metrics()];stop=threading.Event()
     def sample():
      while not stop.wait(.1):samples.append(metrics())
     worker=threading.Thread(target=sample,daemon=True);worker.start()
     prefix='<|im_start|>user\n请将以下文本翻译为'+({'en':'英语','ru':'俄语'}[item['target']])+'，直接输出翻译结果，不要进行任何解释。\n\n'
     try:result=engine.run(prefix,item['text'])
     finally:stop.set();worker.join();samples.append(metrics())
     result.update(type='result',label=a.label,id=item['id'],pass_number=rep,warmup=rep==0,thermal_wait_seconds=waited,memory_before=samples[0],memory_after=samples[-1],memory_peak={k:max(s[k] for s in samples) for k in samples[0]},memory_samples=len(samples),system=system())
     if result['code']==0:result['output_retokenized_count']=engine.lib.ot_mt_count(engine.handle,b'',result['output'].encode(),b'')
     save(result);print(a.label,rep,item['id'],round(result['seconds'],3),result['code'],result['memory_peak']['thermal'],flush=True)
     if result['code']!=0:raise RuntimeError('native decode failed: '+str(result['code']))
  finally:engine.close()
  save(dict(type='completed',system=system(),memory=metrics()))
if __name__=='__main__':main()
