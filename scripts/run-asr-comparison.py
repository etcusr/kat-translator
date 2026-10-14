#!/usr/bin/env python3
"""Run an explicitly built ASR probe, accepting only matching run-id result files."""
import argparse,subprocess,json,time,uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('engine');p.add_argument('--bundle-id',default='app.kattranslator');p.add_argument('--resident',action='store_true');p.add_argument('--timeout',type=int,default=360);a=p.parse_args()
root=Path(__file__).resolve().parent.parent;work=root/'.build/asr-comparison';dev=__import__('os').environ['KAT_IOS_DEVICE'];bundle=a.bundle_id
runid=str(uuid.uuid4());name=a.engine+('-index-resident' if a.resident else '')
def run(args):return subprocess.run(['xcrun','devicectl']+args,capture_output=True,text=True,timeout=60)
env={'OT_ASR_COMPARISON':'1','OT_ASR_ENGINE':a.engine,'OT_ASR_RUN_ID':runid,'OT_ASR_RESIDENT_MT':'1' if a.resident else '0'}
r=run(['device','process','launch','--device',dev,'--terminate-existing','--environment-variables',json.dumps(env),'--',bundle,'-automaticModelLoad','NO'])
if r.returncode:raise SystemExit(r.stdout+r.stderr)
print('START',name,runid,flush=True);last=None;deadline=time.monotonic()+a.timeout
while time.monotonic()<deadline:
 time.sleep(5)
 out=work/(name+'-live.json')
 r=run(['device','copy','from','--device',dev,'--source','Documents/asr-comparison-'+name+'.json','--destination',str(out),'--domain-type','appDataContainer','--domain-identifier',bundle])
 if r.returncode==0:
  d=json.loads(out.read_text())
  if d.get('runID')!=runid:continue
  state=(d['status'],len(d['rows']))
  if state!=last:print(state,flush=True);last=state
  if d['status'] in ['complete','skipped-thermal']:
   target=root/'docs/benchmarks/asr-round2'/ (name+'.json');target.write_text(out.read_text());print('SAVED',target,flush=True)
   raise SystemExit(0 if d['status']=='complete' else 2)
 else:
  status=work/'current-status.txt'
  r=run(['device','copy','from','--device',dev,'--source','Documents/asr-comparison-status.txt','--destination',str(status),'--domain-type','appDataContainer','--domain-identifier',bundle])
  if r.returncode==0 and status.read_text()!=last: last=status.read_text();print(last,flush=True)
raise SystemExit('TIMEOUT; inspect status and device before another run')
