"""Research-only RU→EN shortlist: CPU morphology, short context, tiny model output."""
from functools import lru_cache
from pathlib import Path
import contextlib
import json
import re
import sys
import time
from auto_glossary import SUFFIX, normalized, occurrences

PREFIX = ('<|im_start|>user\n你是术语翻译工具。根据文档语境将指定俄语术语翻译成英语，使用准确、具体的译法。'
          '仅输出JSON字符串数组，顺序与术语相同。每个字符串只包含术语的英语译法，不要翻译整个句子。\n\n')
WORD = re.compile(r'[А-Яа-яЁё]+(?:-[А-Яа-яЁё]+)*')
QUOTE = re.compile(r'«([^»\n]{2,70})»|“([^”\n]{2,70})”|"([^"\n]{2,70})"')
SENTENCE = re.compile(r'[^.!?\n]+(?:[.!?]+|$)')


@lru_cache(maxsize=1)
def morphology():
    # Dependencies remain in an isolated experiment directory, never app runtime.
    deps = Path(__file__).resolve().parents[3] / '.build/mac-fast-terms-2026-10-20/libraries'
    if str(deps) not in sys.path: sys.path.append(str(deps))
    import pymorphy3
    return pymorphy3.MorphAnalyzer()


def select_candidates(blocks, morph, maximum=4):
    text='\n\n'.join(blocks)
    # Parsing cache is document-local; only the morphological dictionaries persist.
    parsed={}
    def parse(word):
        key=normalized(word)
        if key not in parsed: parsed[key]=morph.parse(word)[0]
        return parsed[key]
    def key(value): return ' '.join(parse(word).normal_form for word in WORD.findall(value))
    quoted={}
    for hit in QUOTE.finditer(text):
        value=next(group for group in hit.groups() if group)
        lemma=key(value)
        if lemma: quoted.setdefault(lemma,[]).append((value,hit.start()))
    # Repeated quoted expressions are the most narrowly defined consistency risk.
    groups=[hits for hits in quoted.values() if len(hits)>1]
    method='repeated_quoted_phrases'
    if not groups:
        method='repeated_nouns'
        nouns={}
        for hit in WORD.finditer(text):
            p=parse(hit.group())
            if p.tag.POS=='NOUN' and len(hit.group())>=4:
                nouns.setdefault(p.normal_form,[]).append((hit.group(),hit.start()))
        groups=[hits for hits in nouns.values() if len(hits)>1]
    groups.sort(key=lambda hits:(-len(hits),hits[0][1]))
    sentences=list(SENTENCE.finditer(text));items=[]
    for hits in groups[:maximum]:
        source,position=hits[0]
        sentence_index=next((i for i,s in enumerate(sentences) if s.start()<=position<s.end()),None)
        if sentence_index is None: continue
        context=' '.join(s.group().strip() for s in sentences[max(0,sentence_index-1):sentence_index+2])
        aliases=list(dict.fromkeys(value for value,_ in hits))
        if WORD.fullmatch(source):
            lemma=key(source)
            aliases=list(dict.fromkeys(aliases+[hit.group() for hit in WORD.finditer(text) if key(hit.group())==lemma]))
        items.append(dict(source=source,aliases=aliases,context=context,exact=True))
    # Skip a short standalone heading; retain the opening topic, not just local text.
    body=next((block for block in blocks if re.search(r'[.!?]',block)),blocks[0] if blocks else '')
    lead=' '.join(re.split(r'(?<=[.!?])\s+',body)[:2])
    payload='文章开头: '+lead+'\n'+'\n'.join(f'术语{i+1}: {item["source"]}\n语境: {item["context"]}' for i,item in enumerate(items))
    return items,payload,method



def supplement_nouns(blocks, morph, items, payload, maximum=10):
    """Broaden coverage without repeating context for every common noun."""
    covered={morph.parse(word)[0].normal_form for item in items for word in WORD.findall(item['source'])}
    groups={}
    for hit in WORD.finditer('\n\n'.join(blocks)):
        parsed=morph.parse(hit.group())[0]
        if (parsed.tag.POS=='NOUN' and len(hit.group())>=4
            and not ({'Geox','Name','Surn','Patr','Abbr'} & set(parsed.tag.grammemes))
            and parsed.normal_form not in covered):
            groups.setdefault(parsed.normal_form,[]).append(hit.group())
    items=list(items)
    for values in groups.values():
        if len(values)>1 and len(items)<maximum:
            item=dict(source=values[0],aliases=list(dict.fromkeys(values)),exact=True)
            items.append(item);payload+=f'\n术语{len(items)}: {item["source"]}'
    return items,payload


def parse_targets(raw, items):
    value=raw.strip()
    if value.startswith('```json\n') and value.endswith('\n```'):value=value[8:-4]
    targets=json.loads(value)
    if not isinstance(targets,list) or len(targets)!=len(items):raise ValueError('Wrong number of glossary translations')
    terms=[]
    for item,target in zip(items,targets):
        if not isinstance(target,str) or not 1<=len(target.strip())<=80 or '\n' in target or not re.search('[a-zA-Z]',target):
            raise ValueError('Invalid glossary translation')
        terms.append(dict(source=item['source'],aliases=item['aliases'],exact=True,target=target.strip()))
    return terms


def build_fast_glossary(engine, blocks, include_nouns=False):
    start=time.perf_counter()
    morph=morphology()
    items,payload,method=select_candidates(blocks,morph)
    if include_nouns:
        items,payload=supplement_nouns(blocks,morph,items,payload)
        method += "_plus_nouns"
    selection_seconds=time.perf_counter()-start
    metadata=dict(selection_seconds=selection_seconds,selection_method=method,selected_count=len(items),rejected_entries=0)
    if not items:
        return dict(terms=[],seconds=time.perf_counter()-start,prompt_tokens=0,raw='',first_token_seconds=None,**metadata)
    tokens=engine.count(PREFIX,payload,SUFFIX)
    if tokens>1024:raise ValueError('Selected glossary context exceeds budget; no silent truncation')
    with contextlib.redirect_stdout(sys.stderr):code,raw,first=engine.run(PREFIX,payload,SUFFIX,lambda:False)
    if code:raise RuntimeError(f'Fast glossary generation failed ({code})')
    terms=parse_targets(raw,items)
    text='\n\n'.join(blocks)
    if not all(occurrences(alias,text) for term in terms for alias in term['aliases']):raise ValueError('Unattested glossary source')
    return dict(terms=terms,seconds=time.perf_counter()-start,prompt_tokens=tokens,raw=raw,first_token_seconds=first,**metadata)
