#!/usr/bin/env python3
"""Bounded Pixel GPU matrix sweep; CPU is only the numerical oracle, no model conversion."""
import argparse,json,re,subprocess,time
from pathlib import Path

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial',required=True)
    p.add_argument('--probe-name',default='kat_gpu_probe_wide')
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--suite',choices=['prefill','mtp','edges'],required=True)
    p.add_argument('--modes',nargs='+',choices=['index','strip16','strip32','q6wide','direct','combined'],default=['index','combined','index'])
    a=p.parse_args()
    if not re.fullmatch(r'kat_gpu_probe[a-zA-Z0-9_]*',a.probe_name):p.error('invalid probe name')
    a.out.mkdir(parents=True,exist_ok=False)
    shapes={'prefill':[(q,m,n,k) for q,m,k in [(4,12288,4096),(6,4096,12288),(6,8192,4096)] for n in [46,82,128]],
            'mtp':[(q,m,n,k) for q,m,k in [(4,12288,4096),(6,4096,12288)] for n in [1,2,3]],
            'edges':[(q,m,n,k) for q in [4,6] for m,n,k in [(3,3,256),(129,3,768),(65,65,256),(129,129,512)]]}[a.suite]
    rows=[]
    for shape in shapes:
        for mode in a.modes:
            tile={'direct':'index','combined':'q6wide'}.get(mode,mode)
            env=[f'KAT_VK_MALI_MMQ_TILE={tile}','KAT_VK_MALI_MMV_MULTI=1']
            if mode in ['direct','combined']:env+=['KAT_VK_Q6_DIRECT=1']
            cmd=['adb','-s',a.serial,'shell','env',*env,'/data/local/tmp/'+a.probe_name,*map(str,shape)]
            label=f'{len(rows):03}-{mode}-'+ '-'.join(map(str,shape))
            (a.out/(label+'.command.json')).write_text(json.dumps(cmd,indent=2))
            started=time.time();result=subprocess.run(cmd,capture_output=True,text=True,timeout=180)
            (a.out/(label+'.log')).write_text(result.stdout+result.stderr)
            values=[json.loads(s) for s in result.stdout.splitlines() if s.startswith('{')]
            if result.returncode or len(values)!=1 or not values[0]['passed']:
                raise RuntimeError('GPU/numerical failure: '+label)
            row=dict(values[0],mode=mode,started=started,wallSeconds=time.time()-started)
            rows.append(row);(a.out/'results.json').write_text(json.dumps(rows,indent=2))
            print(json.dumps(row),flush=True)
if __name__=='__main__':main()
