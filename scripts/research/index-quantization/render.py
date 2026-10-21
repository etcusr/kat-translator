#!/usr/bin/env python3
"""Create a local, self-contained source/translation comparison; no network assets."""
import argparse,html,json,re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('results',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
cases=json.loads(Path(__file__).with_name('corpus.json').read_text())['cases'];models=['Q4_K_M','IQ4_XS','Q4_K_S','Q3_K_M'];rows={}
for model in models:
 data=[json.loads(l) for l in (a.results/(model+'.jsonl')).read_text().splitlines()];assert data[-1]['type']=='completed'
 rows[model]={x['id']:x for x in data if x['type']=='result' and x['pass_number']==1}
quality=json.loads((a.results/'quality.json').read_text());issues={(x['id'],x['model']):x['issues'] for x in quality['annotations']}
def issue_ru(x):
 if x['category']=='time':return 'Время встречи изменилось с 08:30 на 09:30.'
 if x['category']=='scientific_entity':return 'Nucleobases (азотистые основания) заменены на «'+x['translation_span']+'» — другой класс веществ.'
 if x['category']=='repetition_loss':return 'Из 12 повторяющихся блоков переведено '+re.search(r'\d+',x['translation_span'])[0]+'. Искусственный тест полноты рассматривается отдельно.'
 return x['explanation']
e=html.escape
body=['<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Index — сравнение переводов</title><style>body{max-width:1400px;margin:32px auto;padding:0 20px;font:16px/1.5 system-ui;background:#f6f7f9;color:#17212b}h1{font-size:28px}.source{white-space:pre-wrap;background:#e9edf2;padding:18px;border-radius:8px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.variant{background:white;border:1px solid #d9dfe6;padding:18px;border-radius:8px}.translation{white-space:pre-wrap}small{color:#536170}section{margin:36px 0 50px}summary{cursor:pointer;font-weight:650;margin:12px 0}label{margin-right:20px}nav{position:sticky;top:0;background:#f6f7f9;padding:10px;border-bottom:1px solid #ddd}@media(max-width:750px){.grid{grid-template-columns:1fr}}</style><h1>Index 9B: одинаковый текст, четыре квантования</h1><p>30 примеров RU↔EN · Mac M3 Pro · llama.cpp/Metal · 21 октября 2026.<br>Показан первый измеряемый проход. Время — весь запрос; прогрев и загрузка модели исключены. Это отдельный стенд, не основная Mac-версия с MLX/MTP2.</p><nav>Показать: ']
for m in models:body.append(f'<label><input type="checkbox" checked onchange="document.querySelectorAll(\'.{m}\').forEach(x=>x.hidden=!this.checked)">{m}</label>')
body.append('</nav>')
for i,c in enumerate(cases,1):
 body.append(f'<section id="{e(c["id"])}"><h2>{i}. {e(c["id"])} <small>{c["source"]} → {c["target"]}</small></h2><div class="source">{e(c["text"])}</div><p><small>Источник корпуса: {e(c["origin"])}</small></p><div class="grid">')
 for m in models:
  r=rows[m][c['id']];notes=''.join('<p style="color:#9d2b22"><strong>Замечание:</strong> '+e(issue_ru(x))+'</p>' for x in issues[(c['id'],m)]);body.append(f'<article class="variant {m}"><strong>{m}</strong> <small>· {r["seconds"]:.2f} с</small><div class="translation">{e(r["output"])}</div>{notes}</article>')
 body.append('</div></section>')
body.append('</html>');a.output.write_text(''.join(body))
print('PASS: rendered 30 sources and 120 translations')
