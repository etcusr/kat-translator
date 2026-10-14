#!/usr/bin/env python3
"""Prepare pinned Wayu speech assets and an offline-only Python text frontend.
Inputs are local downloads; never fetch or execute code from the application.
"""
from pathlib import Path
import ast, shutil, json, hashlib, zipfile
ROOT=Path(__file__).resolve().parent.parent
source=ROOT/'.build/wayu-source'
out=ROOT/'Dependencies/build/wayu/WayuPython'
out.mkdir(parents=True,exist_ok=True)
# Only the TLTK functions needed for pronunciation; no ML classifiers or network code.
raw=(source/'tltk/tltk/nlp.py').read_text().replace("    read_wordtier(ATA_PATH +  '/word.pklz')", '')
tree=ast.parse(raw)
functions={n.name:n for n in tree.body if isinstance(n,ast.FunctionDef)}
needed={'th2ipa','initial','syl_segment','word_segment'}
while True:
 names={n.id for f in list(needed) for n in ast.walk(functions[f]) if isinstance(n,ast.Name)}
 new=needed | (names & functions.keys())
 if new==needed:break
 needed=new
imports='from __future__ import annotations\nimport re, math, os, sys, pickle, bz2, statistics\nfrom copy import deepcopy\nfrom collections import defaultdict\nfrom itertools import product\n'
tltk=out/'tltk';tltk.mkdir(exist_ok=True)
(tltk/'__init__.py').write_text('from . import nlp\n')
(tltk/'nlp.py').write_text('# Derived from TLTK 1.11, BSD-3-Clause; see LICENSE.txt.\n'+imports+'\n\n'.join(ast.get_source_segment(raw,functions[f]) for f in functions if f in needed)+'\ninitial()\n')
for f in ['sylrule.lts','thaisyl.dict','sylseg.3g','thdict','sylform_var.pklz','PhSTrigram.sts']:
 shutil.copy2(source/'tltk/tltk'/f,tltk/f)
shutil.copy2(source/'tltk/tltk-1.11.dist-info/LICENSE.txt',tltk/'LICENSE.txt')
shutil.copytree(source/'pythai/pythainlp',out/'pythainlp',dirs_exist_ok=True)
shutil.copytree(source/'reference/kokoro_thai',out/'kokoro_thai',dirs_exist_ok=True)
shutil.copytree(source/'reference/assets',out/'assets',dirs_exist_ok=True)
# Keep the inference frontend only; training/mining utilities cannot ship in the app.
keep={'__init__.py','g2p.py','normalize.py','vocab.py','word_level.py','name_gate.py'}
for f in (out/'kokoro_thai').glob('*.py'):
 if f.name not in keep:f.unlink()
shutil.copy2(ROOT/'shared/native/Wayu/wayu_frontend.py',out/'wayu_frontend.py')
print(out)

lexdir=source/'misaki/misaki/data'
lex=json.loads((lexdir/'us_silver.json').read_text());lex.update(json.loads((lexdir/'us_gold.json').read_text()))
(out/'english-lexicon.json').write_text(json.dumps(lex,ensure_ascii=False))

# Do not ship unused POS/OCR/wordnet models or unrelated corpora.
required_corpora={'words_th.txt','syllables_th.txt','stopwords_th.txt'}
for f in (out/'pythainlp/corpus').iterdir():
    if f.is_file() and f.suffix not in {'.py'} and f.name not in required_corpora:
        f.unlink()
(out/'tltk/word.pklz').unlink(missing_ok=True)
for cache in out.rglob('__pycache__'):
    shutil.rmtree(cache)
