"""Validate complete candidate runs and render a local, searchable comparison.
No model calls or automatic semantic scores. Invalid harness runs are excluded.
"""
import csv
import hashlib
import html
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
P = ROOT / 'docs/benchmarks/model-search'
corpus = json.loads((P / 'screening.json').read_text())
ids = [r['id'] for r in corpus]
assert len(ids) == len(set(ids)) == 88
digest = hashlib.sha256((P / 'screening.json').read_bytes()).hexdigest()
labels = {'gemma4b': 'TranslateGemma 4B Q4', 'hy18b': 'Hy-MT2 1.8B Q8',
          'index2b': 'Index-Translate 2B Q8', 'hy7b': 'Hy-MT2 7B Q4',
          'hy7b-fidelity': 'Hy-MT2 7B Q4 + fidelity', 'index9b': 'Index-Translate 9B Q4',
          'index9b-fidelity': 'Index-Translate 9B Q4 + fidelity'}
runs, stats = {}, {}
for key, label in labels.items():
    if not (P / key).exists():
        continue
    meta = json.loads((P / key / 'metadata.json').read_text())
    assert meta.get('finished_utc'), f'{key}: unfinished run'
    rows = [json.loads(line) for line in (P / key / 'results.jsonl').read_text().splitlines()]
    assert [r['id'] for r in rows] == ids and meta['count'] == 88
    assert meta['corpus_sha256'] == digest
    for row in rows:
        assert row['code'] == 0 and row['text'].strip() and not row.get('invalid_utf8', False), (key, row)
        assert math.isfinite(row['seconds']) and row['seconds'] >= 0
    times = sorted(r['seconds'] for r in rows)
    runs[key] = {r['id']: r for r in rows}
    stats[key] = dict(label=label, count=len(rows), model_bytes=meta['model_size'],
                      load_seconds=meta['load_seconds'], p50_seconds=statistics.median(times),
                      p95_seconds=times[math.ceil(.95 * len(times)) - 1],
                      measurement='Mac M3 Pro; text MT only; not iPhone latency; no ASR/TTS')
assert len({json.loads((P / k / 'metadata.json').read_text())['runtime_sha256'] for k in runs}) == 1
notes = json.loads((P / 'review.json').read_text())['notes']
for n in notes:
    assert n['model'] in runs and n['id'] in ids
(P / 'summary.json').write_text(json.dumps(dict(corpus_count=88, valid_outputs=sum(v['count'] for v in stats.values()),
    excluded_runs=['hy7b-invalid-template'], statistics=stats), ensure_ascii=False, indent=2) + '\n')
with (P / 'comparison.csv').open('w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'source', 'target', 'input'] + [labels[k] for k in runs])
    for row in corpus:
        writer.writerow([row['id'], row['source'], row['target'], row['text']] + [runs[k][row['id']]['text'] for k in runs])
esc = html.escape
cards = []
for row in corpus:
    entries = []
    for key in runs:
        remarks = [n['note'] for n in notes if n['model'] == key and n['id'] == row['id']]
        entries.append('<div class="result"><strong>' + esc(labels[key]) + '</strong><p>' +
                       esc(runs[key][row['id']]['text']) + '</p>' +
                       ''.join('<p class="note">' + esc(n) + '</p>' for n in remarks) + '</div>')
    cards.append('<article><h2>' + esc(row['id'] + ' · ' + row['source'] + ' → ' + row['target']) +
                 '</h2><p class="source">' + esc(row['text']) + '</p><div class="grid">' + ''.join(entries) + '</div></article>')
page = '''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Сравнение локальных переводчиков</title><style>
body{font:17px/1.5 system-ui,sans-serif;background:#f4f5f7;color:#18212b;max-width:1500px;margin:auto;padding:24px}
input{font:inherit;padding:12px;width:min(90%,650px)}article{margin:24px 0;border-top:2px solid #8793a0;padding-top:12px}
h2{font-size:18px}.source{font-size:20px;font-weight:600}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px}
.result{background:white;border:1px solid #ccd2d8;padding:16px;overflow-wrap:anywhere}.note{color:#713600;border-top:1px solid #ddd;padding-top:10px;font-size:15px}
[hidden]{display:none!important}</style><h1>Сравнение локальных переводчиков</h1>
<p>88 фиксированных заданий: русский ↔ английский, тайский, испанский, немецкий, французский, турецкий.
Mac M3 Pro, один нативный движок приложения. Предварительный разбор ассистента; не независимая экспертиза носителей.
Комментарии отмечают отдельные находки; отсутствие комментария не означает верный перевод. Ошибочный первый шаблон Hy7 исключён.</p>
<label>Поиск по исходнику, переводу или замечаниям<br><input type="search" placeholder="Например: свинину, 083, чаевые"></label>
''' + ''.join(cards) + '''<script>document.querySelector('input').addEventListener('input',e=>{
const q=e.target.value.toLocaleLowerCase();document.querySelectorAll('article').forEach(a=>a.hidden=!a.textContent.toLocaleLowerCase().includes(q))});</script></html>'''
(P / 'comparison.html').write_text(page)
print(json.dumps({'runs': list(runs), 'valid_outputs': sum(v['count'] for v in stats.values()), 'notes': len(notes)}))
