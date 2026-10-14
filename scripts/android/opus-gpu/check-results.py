#!/usr/bin/env python3
"""Fail unless Vulkan really ran and matched the same FP16 graph on CPU."""
from pathlib import Path
import json,re,statistics
root=Path(__file__).resolve().parents[3]
lab=root/'.build/opus-vulkan-lab'
def rows(name,graph=True):
 text=(lab/name).read_text()
 assert 'PROBE ERROR' not in text and 'GGML_ASSERT' not in text,text
 result=[]
 for line in text.splitlines():
  if not line.startswith('RESULT '):continue
  fields=line.split(' ',6 if graph else 2)
  output=json.loads(fields[-1]);assert output
  row={'seconds':float(fields[1]),'output':output}
  if graph:row.update(compute=float(fields[2]),upload=float(fields[3]),graphs=int(fields[4]),nodes=int(fields[5]))
  assert row['seconds']>0
  result.append(row)
 assert result
 return text,result
text,gpu=rows('gpu-second.log');_,cpu=rows('cpu-greedy.log')
assert 'Mali-G715' in text and 'backend=Vulkan0 gpu=1' in text
assert len(gpu)==len(cpu)==2
assert [r['output'] for r in gpu]==[r['output'] for r in cpu]
_,control=rows('ct2-corpus.log',False);_,beam=rows('gpu-corpus-beam5.log')
assert len(control)==len(beam)==9
cases=[]
for i in range(3):
 c=control[i*3:i*3+3];g=beam[i*3:i*3+3]
 assert len({r['output'] for r in c})==len({r['output'] for r in g})==1
 cases.append({'id':i,'ct2_median_seconds':statistics.median(r['seconds'] for r in c),'gpu_median_seconds':statistics.median(r['seconds'] for r in g),'cpu_output':c[0]['output'],'gpu_output':g[0]['output'],'gpu_graphs':g[0]['graphs'],'gpu_compute_median':statistics.median(r['compute'] for r in g)})
report={'gpuVerified':True,'fp16GreedyCpuGpuExactParity':True,'cases':cases,'caveat':'Different precision and beam implementation; a feasibility comparison, not identical decoding algorithms. Cold shader effects included in first run; no temperature guard by user request.'}
(root/'docs/android/benchmarks/2026-10-12-opus-vulkan/results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
