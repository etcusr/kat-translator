#!/usr/bin/env python3
"""Isolated RU→EN context/terminology spike. Never writes app preferences/history."""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import select
import sys
import subprocess
import time
from auto_glossary import build_glossary, occurrences

ROOT = Path(__file__).resolve().parents[3]
SUFFIX = '<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n'
BASE = '<|im_start|>user\n请将以下文本翻译为英语，直接输出翻译结果，不要进行任何解释。\n\n'
MODES = ('plain', 'context', 'context_terms', 'terms', 'auto_terms', 'fast_terms', 'focused_terms')


def plan(text, count, limit=128):
    # Port of the production TranslationChunks planner; exact source coverage.
    rest, pieces = text, []
    sentence = re.compile(r'\n\s*\n|\n|[.!?。！？]["”’\)]?\s+')
    while rest:
        if count(rest) <= limit:
            pieces.append(rest); break
        low, high = 0, len(rest)
        while low < high:
            middle = (low + high + 1) // 2
            if count(rest[:middle]) <= limit: low = middle
            else: high = middle - 1
        if not low: raise ValueError('Unsplitable source token')
        bounded = rest[:low]
        matches = list(sentence.finditer(bounded)) or list(re.finditer(r'\s+', bounded))
        if matches: bounded = bounded[:matches[-1].end()]
        while bounded and count(bounded) > limit: bounded = bounded[:-1]
        if not bounded: raise ValueError('Empty source piece')
        pieces.append(bounded); rest = rest[len(bounded):]
    assert ''.join(pieces) == text
    return pieces


def prompt(mode, text, previous, glossary):
    prefix = BASE
    if mode in ('context_terms', 'terms'):
        relevant = [row for row in glossary if any(bool(occurrences(alias,text)) if row.get('exact') else alias.casefold() in text.casefold() for alias in row['aliases'])]
        if relevant:
            terms = '\n'.join(f"{row['source']} → {row['target']}" for row in relevant)
            prefix = ('<|im_start|>user\n请将以下文本翻译为英语，直接输出翻译结果，不要进行任何解释。'
                      '\n翻译时使用以下术语对应关系，保持术语一致；不要输出术语表：\n' + terms + '\n\n')
    if mode in ('context', 'context_terms') and previous:
        source, translated = previous
        prefix = BASE + source + SUFFIX + translated + '<|im_end|>\n' + prefix
    return prefix, text, SUFFIX


class Experiment:
    def __init__(self):
        os.environ['HF_HUB_OFFLINE'] = '1'
        os.environ['TRANSFORMERS_OFFLINE'] = '1'
        sys.path.insert(0, str(ROOT / '.build/mac-index-mlx-mtp/omlx'))
        sys.path.insert(0, str(ROOT / 'shared/native/IndexMLX'))
        with contextlib.redirect_stdout(sys.stderr):
            from index_mlx import Engine
            started = time.perf_counter()
            self.engine = Engine(str(Path.home() / 'Library/Application Support/OfflineTranslator/TranslationPackages/index-translate-9b-mlx-mtp2'))
            self.load_seconds = time.perf_counter() - started
        self.count = lambda text: self.engine.count('', text, '')

    def run(self, case, mode, emit=lambda event: None):
        if mode not in MODES: raise ValueError('Unknown mode')
        start = time.perf_counter()
        blocks = case['blocks']
        automatic = None
        if mode in ('auto_terms', 'fast_terms', 'focused_terms'):
            emit(dict(event='glossary_start'))
            if mode in ('fast_terms','focused_terms'):
                from fast_glossary import build_fast_glossary
                automatic = build_fast_glossary(self.engine, blocks, include_nouns=mode=='focused_terms')
            else:
                automatic = build_glossary(self.engine, blocks)
            glossary = automatic['terms']
            emit(dict(event='glossary', terms=glossary, seconds=automatic['seconds'], rejected=automatic['rejected_entries']))
        else:
            glossary = case.get('glossary', [])
        planned = [plan(text, self.count) for text in blocks]
        output, trace, previous = [], [], None
        first_part = first_body_part = first_token = first_body_token = None
        total = sum(map(len, blocks)); completed = 0
        for bi, pieces in enumerate(planned):
            translated, separator = '', ' '
            for pi, piece in enumerate(pieces):
                text = piece.strip()
                prefix, text, suffix = prompt('terms' if mode in ('auto_terms', 'fast_terms', 'focused_terms') else mode, text, previous, glossary)
                prompt_tokens = self.engine.count(prefix, text, suffix)
                if prompt_tokens > 1024:
                    raise ValueError('Context exceeds experiment budget; no silent fallback')
                call_start = time.perf_counter()
                with contextlib.redirect_stdout(sys.stderr):
                    code, result, first = self.engine.run(prefix, text, suffix, lambda: False)
                seconds = time.perf_counter() - call_start
                if code: raise RuntimeError(f'Inference failed with code {code}; block {bi}, piece {pi}')
                elapsed = time.perf_counter() - start
                if first_part is None: first_part = elapsed
                if first_token is None: first_token = call_start-start+first
                if bi > 0 and first_body_part is None: first_body_part = elapsed
                if bi > 0 and first_body_token is None: first_body_token = call_start-start+first
                translated = translated + separator + result if translated else result
                whitespace = piece[len(piece.rstrip()):]
                separator = '\n\n' if '\n\n' in whitespace else ('\n' if '\n' in whitespace else ' ')
                completed += len(piece)
                current = '\n\n'.join(output+[translated])
                trace.append(dict(block=bi, piece=pi, source=text, output=result, source_characters=len(piece),
                                  prompt_tokens=prompt_tokens, seconds=seconds, elapsed=elapsed))
                emit(dict(event='partial', output=current, completed=completed, total=total, seconds=elapsed))
                previous = (text, result)
            output.append(translated)
        return dict(mode=mode, seconds=time.perf_counter()-start, first_part_seconds=first_part,
                    first_body_part_seconds=first_body_part, first_token_seconds=first_token,
                    first_body_token_seconds=first_body_token, output='\n\n'.join(output), trace=trace,
                    block_characters=list(map(len, blocks)), pieces_per_block=list(map(len, planned)),
                    glossary=automatic, glossary_seconds=automatic['seconds'] if automatic else 0)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--serve', action='store_true')
    parser.add_argument('--swift-planner', type=Path)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--modes', default='plain,context,context_terms,terms')
    args=parser.parse_args()
    modes=tuple(args.modes.split(','))
    if not modes or any(mode not in MODES for mode in modes) or len(set(modes))!=len(modes): parser.error('Invalid modes')
    case=json.loads(args.fixture.read_text())
    experiment=Experiment()
    try:
        parity = None
        if args.swift_planner:
            child = subprocess.Popen([str(args.swift_planner), str(args.fixture)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            for line in child.stdout:
                item = json.loads(line)
                if 'count' in item:
                    child.stdin.write(str(experiment.count(item['count']))+'\n'); child.stdin.flush()
                else:
                    actual = [plan(block,experiment.count) for block in case['blocks']]
                    assert item['pieces'] == actual, 'Python and production Swift boundaries differ'
                    parity = dict(equal=True, pieces_per_block=list(map(len,actual)))
            assert child.wait()==0 and parity
        if args.serve:
            print(json.dumps(dict(event='ready', load_seconds=experiment.load_seconds)),flush=True)
            while select.select([sys.stdin], [], [], 300)[0]:
                line = sys.stdin.readline()
                if not line: break
                request=json.loads(line)
                try:
                    result=experiment.run(request.get('case',case),request['mode'],lambda event:print(json.dumps(event,ensure_ascii=False),flush=True))
                    print(json.dumps(dict(event='done',**result),ensure_ascii=False),flush=True)
                except Exception as error: print(json.dumps(dict(event='error',error=str(error))),flush=True)
        else:
            if not args.output: parser.error('--output is required without --serve')
            # Full warm-up pass remains separately identified; never mixed into medians.
            report=dict(fixture_sha256=hashlib.sha256(args.fixture.read_bytes()).hexdigest(),
                        load_seconds=experiment.load_seconds, planner_parity=parity, results=[])
            for repeat in range(args.repeats+1):
                order=modes[repeat%len(modes):]+modes[:repeat%len(modes)]
                for mode in order:
                    row=experiment.run(case,mode)
                    row.update(repeat=repeat,phase='warmup' if repeat==0 else 'warm')
                    report['results'].append(row)
                    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
                    print(f"{repeat} {mode} total={row['seconds']:.3f} first_body={row['first_body_part_seconds']:.3f}",file=sys.stderr,flush=True)
    finally: experiment.engine.close()

if __name__=='__main__': main()
