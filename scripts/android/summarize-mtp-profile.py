#!/usr/bin/env python3
"""Summarize synchronized diagnostic MTP stages; not normal application latency."""
import argparse
from collections import defaultdict
import json
import math
import re
from pathlib import Path


def summarize(text, prompt_tokens=46):
    requests=[]
    current=None
    consumed=0
    phase='prefill'
    for line in text.splitlines():
        if 'processing task,' in line:
            current={'stageMs':defaultdict(float),'stageCalls':defaultdict(int),'targetBatches':[], 'complete':False}
            requests.append(current);consumed=0;phase='prefill'
        if 'KAT_MTP_STAGE' in line:
            match=re.search(r'KAT_MTP_STAGE name=(\w+) tokens=(\d+) ms=(\S+)',line)
            if not match or current is None:
                raise ValueError('Stage without a request or malformed record')
            name,n,ms=match[1],int(match[2]),float(match[3])
            if not math.isfinite(ms) or ms<0:
                raise ValueError('Invalid stage duration')
            if name=='target':
                phase='prefill' if consumed<prompt_tokens else 'decode'
                if phase=='prefill':
                    consumed+=n
                    if consumed>prompt_tokens:raise ValueError('Mixed prompt/decode batch cannot be attributed')
                current['targetBatches'].append({'phase':phase,'tokens':n,'ms':ms})
            key=phase+'.'+name
            current['stageMs'][key]+=ms;current['stageCalls'][key]+=1
            if name=='begin':phase='decode'
        if current is not None and 'total time =' in line:
            current['complete']=True
    if not requests or not any(r['stageMs'] for r in requests):
        raise ValueError('No diagnostic stages found')
    return {'warning':'GPU fences serialize stages; compare unprofiled runs separately. Stage totals exclude other server work.',
            'promptTokens':prompt_tokens,'requests':requests}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log',type=Path)
    parser.add_argument('--prompt-tokens',type=int,default=46)
    args=parser.parse_args()
    print(json.dumps(summarize(args.log.read_text(),args.prompt_tokens),indent=2))
