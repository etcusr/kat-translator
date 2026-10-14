"""Reproduce the fixed film-phrase test using the app's local MT bridge and Swift prompt.
No network calls; no ASR/TTS; reverse translation is diagnostic, never an independent judge.
Run from the repository root. Scores are added separately after reading the Thai outputs.
"""
import argparse, ctypes as c, hashlib, json, platform, re, subprocess, time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--corpus', type=Path, default=ROOT/'docs/benchmarks/ru-th-film100/corpus.json')
p.add_argument('--output', type=Path, default=ROOT/'docs/benchmarks/ru-th-film100/run')
args = p.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
assert not (args.output/'results.jsonl').exists(), 'Choose a fresh output directory'
rows = json.loads(args.corpus.read_text())
assert len(rows) == 100 and len({x['id'] for x in rows}) == 100 and len({x['ru'] for x in rows}) == 100
assert all(x['source_checked'] and x['ru'].strip() and '\0' not in x['ru'] for x in rows)

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while b := f.read(4*1024*1024): h.update(b)
    return h.hexdigest()

model = ROOT/'model-store/downloads/translategemma-4b-it.Q4_K_M.gguf'
library = ROOT/'Dependencies/build/translation/macosx/TranslationRuntime.framework/TranslationRuntime'
swift_path = ROOT/'shared/packages/OfflineCore/Sources/OfflineCore/TranslationPrompt.swift'
swift = swift_path.read_text()
template = re.search(r'return "(<bos>.*?)"', swift).group(1)
suffix = json.loads('"'+re.search(r'public static let suffix = "(.*?)"', swift).group(1)+'"').encode()
names = {'ru':'Russian', 'th':'Thai'}
def prefix(src, dst):
    text = template
    for k,v in {'s': names[src], 't': names[dst], 'source.rawValue':src, 'target.rawValue':dst}.items():
        text = text.replace('\\('+k+')',v)
    return json.loads('"'+text+'"').encode()

model_sha = sha(model)
assert model_sha == '81200d03e843d2ec1ece6eeafe7d13cb6e5211e1fcd336ade55790b683a08330'
metadata = dict(started_utc=datetime.now(timezone.utc).isoformat(), git_head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
    platform=platform.platform(), model=model.name, model_sha256=model_sha, runtime_sha256=sha(library),
    runtime_source_sha256=sha(ROOT/'shared/native/TranslationRuntime/TranslationRuntime.cpp'), prompt_source_sha256=sha(swift_path),
    corpus_sha256=sha(args.corpus), count=len(rows), decoding='greedy; n_ctx=2048; output limit 512 tokens; KV cleared before every call',
    runtime_lock=json.loads((ROOT/'Dependencies/runtime.lock.json').read_text())['llama'],
    forward_prefix=prefix('ru','th').decode(), reverse_prefix=prefix('th','ru').decode(), suffix=suffix.decode(),
    review='Separate assistant review of Thai text; same-model back-translation is not an independent evaluation.')
(args.output/'metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
lib=c.CDLL(str(library));lib.ot_mt_load.argtypes=[c.c_char_p];lib.ot_mt_load.restype=c.c_void_p
lib.ot_mt_free.argtypes=[c.c_void_p];lib.ot_mt_flag_create.restype=c.c_void_p;lib.ot_mt_flag_free.argtypes=[c.c_void_p]
lib.ot_mt_count.argtypes=[c.c_void_p,c.c_char_p,c.c_char_p,c.c_char_p];lib.ot_mt_count.restype=c.c_int
lib.ot_mt_run.argtypes=[c.c_void_p,c.c_char_p,c.c_char_p,c.c_char_p,c.c_void_p,c.c_char_p,c.c_size_t,c.POINTER(c.c_double)];lib.ot_mt_run.restype=c.c_int
start=time.monotonic();handle=lib.ot_mt_load(str(model).encode());assert handle,'Model load failed'
metadata['load_seconds']=time.monotonic()-start

def translate(text, src, dst):
    prompt=prefix(src,dst);tokens=lib.ot_mt_count(handle,prompt,text.encode(),suffix)
    assert 0<tokens<=1536
    flag=lib.ot_mt_flag_create();assert flag
    out=c.create_string_buffer(65536);first=c.c_double(-1);t=time.monotonic()
    try:code=lib.ot_mt_run(handle,prompt,text.encode(),suffix,flag,out,len(out),c.byref(first))
    finally:lib.ot_mt_flag_free(flag)
    return dict(text=out.value.decode().strip(),code=code,seconds=time.monotonic()-t,first_token_seconds=first.value,input_tokens=tokens)
try:
    with (args.output/'results.jsonl').open('w') as f:
        for row in rows:
            forward=translate(row['ru'],'ru','th')
            backward=translate(forward['text'],'th','ru') if forward['code']==0 and forward['text'] else None
            item=dict(id=row['id'],forward=forward,backward=backward)
            f.write(json.dumps(item,ensure_ascii=False)+'\n');f.flush()
            print(row['id'],row['ru'],'=>',forward['text'],flush=True)
finally:
    lib.ot_mt_free(handle)
metadata['finished_utc']=datetime.now(timezone.utc).isoformat()
(args.output/'metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
