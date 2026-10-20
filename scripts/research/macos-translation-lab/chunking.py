"""Experimental, lossless source splitting; no model/runtime modifications."""
import re


def clip(text, count, limit, tail=False):
    if count(text)<=limit:return text
    lo,hi=0,len(text)
    while lo<hi:
        mid=(lo+hi+1)//2
        piece=text[-mid:] if tail else text[:mid]
        if count(piece)<=limit:lo=mid
        else:hi=mid-1
    return (text[-lo:] if tail else text[:lo]) if lo else ''


def plan(text,count,limit=128):
    if limit<1:raise ValueError('Positive token budget required')
    chunks=[];start=0
    while start<len(text):
        rest=text[start:]
        bounded=clip(rest,count,limit)
        if not bounded:raise ValueError('One character exceeds chunk budget')
        end=start+len(bounded)
        if end<len(text):
            # Prefer a complete paragraph, then dialogue turn or sentence.
            candidates=list(re.finditer(r'\n\s*\n|\n|[.!?。！？][\"”’\)]?\s+',bounded))
            if candidates:
                end=start+candidates[-1].end()
            else:
                spaces=list(re.finditer(r'\s+',bounded))
                if spaces:end=start+spaces[-1].end()
        raw=text[start:end]
        whitespace=re.search(r'\s*$',raw).group()
        separator='\n\n' if '\n\n' in whitespace else ('\n' if '\n' in whitespace else ' ')
        chunks.append(dict(start=start,end=end,raw=raw,separator=separator))
        start=end
    assert ''.join(c['raw'] for c in chunks)==text
    return chunks


START = '[[KAT_START]]'
END = '[[KAT_END]]'


def context_input(text,chunk,count):
    if START in text or END in text:
        raise ValueError('Source contains reserved experimental boundary markers')
    before=clip(text[:chunk['start']],count,64,tail=True)
    after=clip(text[chunk['end']:],count,32)
    current=text[chunk['start']:chunk['end']].strip()
    return f'{before}\n\n{START}\n{current}\n{END}\n\n{after}'


def extract_current(output):
    if output.count(START)!=1 or output.count(END)!=1:
        raise ValueError('Translation did not preserve unique chunk boundaries')
    start=output.index(START)+len(START);end=output.index(END)
    if end<=start or not output[start:end].strip():
        raise ValueError('Translation returned empty or reversed chunk boundaries')
    return output[start:end].strip()


def translate(engine,text,target,suffix,mode='chunk_context',progress=None):
    count=lambda value:len(engine.tokenizer.encode(value,add_special_tokens=False))
    chunks=plan(text,count)
    import time
    started=time.perf_counter();outputs=[];metrics=[];first_token=-1.;first_chunk=-1.
    for index,chunk in enumerate(chunks):
        if not chunk['raw'].strip():continue
        lang={'ru':'俄语','en':'英语'}[target]
        prefix=f'<|im_start|>user\n请将以下文本翻译为{lang}，直接输出翻译结果，不要进行任何解释。\n\n'
        contextual=mode=='chunk_context' and len(chunks)>1
        current=chunk['raw'].strip()
        if contextual:
            prefix=f'<|im_start|>user\n请将以下文本翻译为{lang}，直接输出翻译结果，不要进行任何解释。保留 [[KAT_START]] 和 [[KAT_END]] 标记，位置不变。\n\n'
            current=context_input(text,chunk,count)
        input_tokens=engine.count(prefix,current,suffix)
        if input_tokens>1024:raise ValueError('Chunk prompt exceeds reserved input budget')
        step=time.perf_counter()
        code,output,first=engine.run(prefix,current,suffix,lambda:False)
        boundary_error=None
        raw_output=output
        if code==0 and contextual:
            try:output=extract_current(output)
            except ValueError as error:
                code=-4;output='';boundary_error=str(error)
        metrics.append(dict(index=index,start=chunk['start'],end=chunk['end'],
                            input_tokens=input_tokens,seconds=time.perf_counter()-step,
                            code=code,output=output,raw_output=raw_output,boundary_error=boundary_error))
        if code!=0:
            return dict(code=code,output='',seconds=time.perf_counter()-started,
                        first_token_seconds=first_token,first_chunk_seconds=first_chunk,
                        chunks=metrics,complete=False)
        if first_token<0:first_token=step-started+first
        outputs.append(output+chunk['separator'])
        if first_chunk<0:first_chunk=time.perf_counter()-started
        combined=''.join(outputs).strip()
        if progress:progress(dict(event='progress',output=combined,completed=index+1,total=len(chunks)))
    return dict(code=0 if outputs else -1,output=''.join(outputs).strip(),
                seconds=time.perf_counter()-started,first_token_seconds=first_token,
                first_chunk_seconds=first_chunk,chunks=metrics,complete=bool(outputs))
