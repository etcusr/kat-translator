"""Document-local glossary generated from source only; strict, attested entries."""
import contextlib
import json
import re
import sys
import time

PREFIX = ('<|im_start|>user\n从下面的俄语文档中提取最多10个需要一致翻译的术语（专业词、缩写、重复的重要词）。'
          '根据全文语境给出英语译法。只输出JSON数组，每项只有source和target字段。'
          'source必须是文档中逐字出现的俄语片段，target是简短英语术语。不要翻译整篇文章，不要解释。\n\n')
SUFFIX = '<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n'


def normalized(text):
    return text.casefold().replace('ё','е')


def stem(word):
    # Conservative single-word inflection grouping, not a morphological analyzer.
    value=normalized(word)
    suffix=re.search(r'(иями|ями|ами|иях|ого|его|ому|ему|ов|ев|ей|ом|ем|ам|ям|ах|ях|ой|ий|ый|ая|ое|ые|ие|ою|ею|у|ю|а|я|ы|и|е|о)$',value)
    if suffix and suffix.start()>=5: return value[:suffix.start()]
    return value


def occurrences(term,text):
    pattern=''.join('[её]' if ch in 'её' else re.escape(ch) for ch in normalized(term))
    return [match.group() for match in re.finditer(r'(?<!\w)'+pattern+r'(?!\w)',text,re.I)]


def validate_glossary(raw, text):
    value=raw.strip()
    if value.startswith('```json\n') and value.endswith('\n```'): value=value[8:-4]
    rows=json.loads(value)
    if not isinstance(rows,list) or len(rows)>10: raise ValueError('Expected at most 10 glossary entries')
    terms=[];rejected=0
    words=re.findall(r'(?<!\w)[А-Яа-яЁё]+(?!\w)',text)
    for row in rows:
        if not isinstance(row,dict) or set(row)!= {'source','target'}: raise ValueError('Invalid glossary fields')
        source,target=row['source'],row['target']
        if not isinstance(source,str) or not isinstance(target,str): raise ValueError('Invalid glossary value')
        if not 1<=len(source)<=80 or not 1<=len(target)<=100 or '\n' in source+target or not re.search('[a-zA-Z]',target):
            raise ValueError('Invalid glossary term')
        aliases=occurrences(source,text)
        if not aliases:
            rejected+=1;continue
        if re.fullmatch('[А-Яа-яЁё]+',source) and len(stem(source))>=5:
            aliases += [word for word in words if stem(word)==stem(source)]
        aliases=list(dict.fromkeys(aliases))
        overlap=next((old for old in terms if set(map(normalized,old['aliases'])) & set(map(normalized,aliases))),None)
        if overlap:
            if normalized(overlap['target'])!=normalized(target): raise ValueError('Conflicting automatic term translations')
            overlap['aliases']=list(dict.fromkeys(overlap['aliases']+aliases));continue
        terms.append(dict(source=aliases[0],target=target.strip(),aliases=aliases,exact=True))
    return terms,rejected


def build_glossary(engine, blocks):
    start=time.perf_counter();text='\n\n'.join(blocks)
    tokens=engine.count(PREFIX,text,SUFFIX)
    if tokens>1024: raise ValueError('Document exceeds automatic-glossary input limit; no text was truncated')
    with contextlib.redirect_stdout(sys.stderr):
        code,raw,first=engine.run(PREFIX,text,SUFFIX,lambda:False)
    if code: raise RuntimeError(f'Automatic glossary generation failed ({code}); no manual fallback')
    terms,rejected=validate_glossary(raw,text)
    if not terms: raise ValueError('No source-attested automatic terms; no manual fallback')
    return dict(terms=terms,rejected_entries=rejected,seconds=time.perf_counter()-start,
                prompt_tokens=tokens,raw=raw,first_token_seconds=first)
