"""Render round-two raw comparisons, retaining failures and review limitations."""
import csv
import hashlib
import html
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
P = ROOT / 'docs/benchmarks/model-search-round2'
corpus = json.loads((P / 'screening.json').read_text())
ids = [r['id'] for r in corpus]
assert len(ids) == len(set(ids)) == 140
digest = hashlib.sha256((P / 'screening.json').read_bytes()).hexdigest()
labels = {'index9b': 'Index-Translate 9B Q4', 'qwen9b': 'Qwen3.5 9B Q4',
          'mil4b': 'MiLMMT-46 4B v1.0 Q4', 'mil12b': 'MiLMMT-46 12B v1.0 Q4'}
runs, stats, runtimes = {}, {}, set()
for key, label in labels.items():
    meta = json.loads((P / key / 'metadata.json').read_text())
    assert meta.get('finished_utc'), f'{key}: unfinished run'
    rows = [json.loads(line) for line in (P / key / 'results.jsonl').read_text().splitlines()]
    assert [r['id'] for r in rows] == ids and meta['count'] == len(ids)
    assert meta['corpus_sha256'] == digest
    runtimes.add(meta['runtime_sha256'])
    for row in rows:
        assert math.isfinite(row['seconds']) and row['seconds'] >= 0
    good = [r for r in rows if r['code'] == 0 and r['text'].strip() and not r.get('invalid_utf8')]
    times = sorted(r['seconds'] for r in good)
    runs[key] = {r['id']: r for r in rows}
    stats[key] = dict(label=label, attempts=len(rows), technically_valid=len(good),
        failures=len(rows)-len(good), model_bytes=meta['model_size'], load_seconds=meta['load_seconds'],
        p50_seconds=statistics.median(times) if times else None,
        p95_seconds=times[math.ceil(.95*len(times))-1] if times else None,
        measurement='Mac M3 Pro; text MT only; successful calls; preliminary latency, not iPhone')
assert len(runtimes) == 1, 'Runtime changed between runs'
notes = json.loads((P / 'review.json').read_text())['notes'] if (P / 'review.json').exists() else []
for n in notes:
    assert n['model'] in runs and n['id'] in ids
(P / 'summary.json').write_text(json.dumps(dict(corpus_count=len(ids),
    attempts=sum(v['attempts'] for v in stats.values()), statistics=stats,
    review='Non-blind assistant screening; not native-speaker validation or a quality percentage',
    out_of_scope={'mil4b': ['new-043', 'new-044'], 'mil12b': ['new-043', 'new-044']}),
    ensure_ascii=False, indent=2)+'\n')
with (P / 'comparison.csv').open('w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'source', 'target', 'group', 'input'] +
                    [f'{labels[k]} {field}' for k in runs for field in ['output', 'code', 'seconds']])
    for row in corpus:
        writer.writerow([row['id'], row['source'], row['target'], row['group'], row['text']] +
            [runs[k][row['id']][field] for k in runs for field in ['text', 'code', 'seconds']])
esc = html.escape
cards = []
for row in corpus:
    entries = []
    for key in runs:
        r = runs[key][row['id']]
        remarks = [n['note'] for n in notes if n['model'] == key and n['id'] == row['id']]
        status = f"{r['seconds']:.2f} с · код {r['code']}"
        if r.get('invalid_utf8'): status += ' · ошибка UTF-8'
        if key.startswith('mil') and 'uk' in (row['source'], row['target']):
            status += ' · украинский вне заявленной поддержки'
        entries.append('<div class="result"><strong>' + esc(labels[key]) + '</strong><p>' +
            esc(r['text'] or '[пустой ответ]') + '</p><small>' + esc(status) + '</small>' +
            ''.join('<p class="note">' + esc(n) + '</p>' for n in remarks) + '</div>')
    cards.append('<article><h2>' + esc(row['id']+' · '+row['source']+' → '+row['target']) +
        '</h2><p class="source">' + esc(row['text']) + '</p><p>Проверяем: ' + esc(row['meaning']) +
        '</p><div class="grid">' + ''.join(entries) + '</div></article>')
page = '''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Index, Qwen и Xiaomi — локальное сравнение</title><style>
body{font:17px/1.5 system-ui,sans-serif;background:#f4f5f7;color:#18212b;max-width:1700px;margin:auto;padding:24px}
input{font:inherit;padding:12px;width:min(90%,650px)}article{margin:24px 0;border-top:2px solid #8793a0;padding-top:12px}
h2{font-size:18px}.source{font-size:20px;font-weight:600}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:12px}
.result{background:white;border:1px solid #ccd2d8;padding:16px;overflow-wrap:anywhere}.note{color:#713600;border-top:1px solid #ddd;padding-top:10px;font-size:15px}
small{color:#505861}[hidden]{display:none!important}</style><h1>Index, Qwen и Xiaomi</h1>
<p>140 заданий × 4 модели. 88 регрессионных и 52 новых. Mac M3 Pro, движок приложения.
Комментарии — предварительный разбор ассистента, без слепой экспертизы носителей. Отсутствие комментария не означает верный перевод.
Задержки относятся только к переводу текста на Mac. Украинский не заявлен у MiLMMT.</p>
<p>Все сырые результаты, параметры и ошибки сохранены. Код 0 означает технический успех, а не верный смысл.</p>
<label>Поиск по исходнику, переводу, языку или замечаниям<br><input type="search" placeholder="Например: номер, new-009, отрицание"></label>
''' + ''.join(cards) + '''<script>document.querySelector('input').addEventListener('input',e=>{
const q=e.target.value.toLocaleLowerCase();document.querySelectorAll('article').forEach(a=>a.hidden=!a.textContent.toLocaleLowerCase().includes(q))});</script></html>'''
(P / 'comparison.html').write_text(page)
print(json.dumps(stats, ensure_ascii=False, indent=2))
