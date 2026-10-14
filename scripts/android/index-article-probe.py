#!/usr/bin/env python3
"""Compare whole/sentence Index translation on a supplied local text. No app mutation.

Uses the separately installed kat_mtp_probe; serialize with all other GPU tests.
Reports completion/number checks, not a general translation quality score.
"""
import argparse, json, os, re, subprocess, time, urllib.request, urllib.error
from pathlib import Path


def segments(text):
    # Same boundaries as Android OpusSegments, retaining all original characters.
    rx=r'[.!?]["”»]?(\s+)(?=[A-ZА-ЯЁІЇЄҐЎ"“«])|(\n\s*\n)'
    cuts=[0]+[m.start(1) if m.group(1) else m.start(2) for m in re.finditer(rx,text)]+[len(text)]
    return [text[a:b] for a,b in zip(cuts,cuts[1:]) if b>a]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial',default=os.environ.get('ANDROID_SERIAL'),required=not bool(os.environ.get('ANDROID_SERIAL')))
    p.add_argument('--input',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--model',default='/sdcard/Android/data/org.openoffline.translator.android/files/Index-Translate-9B.Q4_K_M.gguf')
    p.add_argument('--target',choices=['en','ru'],default='en')
    p.add_argument('--draft',type=int,choices=[0,1],default=1)
    p.add_argument('--mode',choices=['whole','sentences'],default='whole')
    p.add_argument('--repeats',type=int,default=2)
    a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False)
    text=a.input.read_text().strip();parts=[text] if a.mode=='whole' else segments(text)
    assert ''.join(parts)==text
    adb=['adb','-s',a.serial]
    def run(*args):return subprocess.run(adb+list(args),check=True,capture_output=True,text=True,timeout=30).stdout.strip()
    port=run('forward','tcp:0','tcp:18891');url='http://127.0.0.1:'+port
    http=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    command=adb+['shell','env','KAT_VK_MALI_MMQ_TILE=q6wide','KAT_VK_Q6_DIRECT=1','KAT_VK_MALI_MMV_MULTI=1','/data/local/tmp/kat_mtp_probe','-m',a.model,'-c','2048','-b','512','-ub','128','-t','4','-tb','4','-ngl','99','-dev','Vulkan0','-fa','on','-np','1','--host','127.0.0.1','--port','18891','--no-webui','--no-warmup','--no-cache-prompt','--ctx-checkpoints','0','--spec-type','draft-mtp' if a.draft else 'none']
    if a.draft:command+=['--spec-draft-n-max','1','--spec-draft-n-min','1']
    (a.out/'command.json').write_text(json.dumps(command,indent=2))
    (a.out/'parts.json').write_text(json.dumps(parts,ensure_ascii=False,indent=2))
    server=None
    try:
      with (a.out/'server.log').open('w') as log:
        server=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
        deadline=time.monotonic()+180
        while True:
          if server.poll() is not None:raise RuntimeError('Server exited; inspect server.log')
          try:
            with http.open(url+'/health',timeout=2) as r:
              if r.status==200:break
          except (OSError,urllib.error.URLError):pass
          if time.monotonic()>deadline:raise TimeoutError('Startup timeout')
          time.sleep(1)
        rows=[]
        for repeat in range(a.repeats):
          begin=time.monotonic();results=[]
          for i,part in enumerate(parts):
            target={'en':'英语','ru':'俄语'}[a.target]
            prompt=f'<|im_start|>user\n请将以下文本翻译为{target}，直接输出翻译结果，不要进行任何解释。\n\n'+part+'<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n'
            req={'prompt':prompt,'temperature':0,'seed':1,'n_predict':1024,'cache_prompt':False,'stream':False,'return_tokens':True}
            (a.out/f'request-{i}.json').write_text(json.dumps(req,ensure_ascii=False,indent=2))
            start=time.monotonic()
            with http.open(urllib.request.Request(url+'/completion',json.dumps(req).encode(),{'Content-Type':'application/json'}),timeout=300) as response:r=json.load(response)
            r['wallSeconds']=time.monotonic()-start
            (a.out/f'response-{repeat}-{i}.json').write_text(json.dumps(r,ensure_ascii=False,indent=2))
            assert not r['truncated'] and r.get('stop_type')=='eos', 'Truncated or non-EOS generation'
            assert r['timings']['cache_n']==0 and r['timings']['prompt_n']>0
            assert r['content'].strip() and '<think>' not in r['content']
            for number in re.findall(r'\d+',part):assert number in r['content'], 'Missing number '+number
            results.append(r)
          row={'repeat':repeat,'parts':len(parts),'wallSeconds':time.monotonic()-begin,'promptSeconds':sum(r['timings']['prompt_ms'] for r in results)/1000,'decodeSeconds':sum(r['timings']['predicted_ms'] for r in results)/1000,'promptTokens':sum(r['timings']['prompt_n'] for r in results),'outputTokens':sum(r['timings']['predicted_n'] for r in results),'drafted':sum(r['timings'].get('draft_n',0) for r in results),'accepted':sum(r['timings'].get('draft_n_accepted',0) for r in results),'text':'\n'.join(r['content'].strip() for r in results)}
          rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
          (a.out/'summary.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
    finally:
      subprocess.run(adb+['shell','pkill','-x','kat_mtp_probe'],timeout=30,check=False)
      if server:
        try:server.wait(timeout=15)
        except subprocess.TimeoutExpired:server.kill();server.wait()
      run('forward','--remove','tcp:'+port)

if __name__=='__main__':main()
