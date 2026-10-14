#!/usr/bin/env python3
"""Summarize the opt-in native article benchmark; never infer missing results."""
import argparse
import hashlib
import json
import statistics
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--input', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--allow-partial', action='store_true', help='Report completed articles after an intentional stop')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
reports, traces = {}, {}
for device in ['mac', 'ios']:
    report = json.loads((a.input / f'{device}-report.json').read_text())
    if (not report.get('completed') or len(report['rows']) != 8) and not a.allow_partial:
        raise SystemExit(f'{device}: full eight-run series is not complete')
    assert report['rows'], f'{device}: no completed articles'
    assert len({(r['id'], r['pass']) for r in report['rows']}) == len(report['rows'])
    reports[device] = report
    traces[device] = [x for line in (a.input / f'{device}-trace.jsonl').read_text().splitlines()
                      if (x := json.loads(line))['pid'] == report['pid']]
    (a.output / f'{device}-results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    (a.output / f'{device}-trace.jsonl').write_text(''.join(json.dumps(x) + '\n' for x in traces[device]))
assert reports['mac']['articles'] == reports['ios']['articles'], 'Different source corpus'
assert reports['mac']['modelSHA256'] == reports['ios']['modelSHA256'], 'Different weights'

rows = []
for source in reports['mac']['articles']:
    assert hashlib.sha256(source['text'].encode()).hexdigest() == source['sha256']
    item = {'id': source['id'], 'title': source['title'], 'url': source['url'], 'characters': source['characters']}
    outputs = []
    for device in ['mac', 'ios']:
        runs = [r for r in reports[device]['rows'] if r['id'] == source['id']]
        measurements = []
        for r in runs:
            assert r['progress'][-1]['completedCharacters'] == r['sourceCharacters']
            calls = [x for x in traces[device] if x['phase'] == 'translate.complete'
                     and r['startedAt'] <= x['timestamp'] <= r['finishedAt']]
            successes = [x for x in calls if x['code'] == 0]
            retries = [x for x in calls if x['code'] == 1]
            assert len(successes) == r['fragments'], 'Trace/report call count mismatch'
            text = r['translation']
            outputs.append(text)
            (a.output / f"{source['id']}-{device}-pass{r['pass']}.txt").write_text(text + '\n')
            measurements.append({'pass': r['pass'], 'seconds': r['seconds'],
                'firstTokenSeconds': r['firstTokenSeconds'],
                'initialParts': r['progress'][0]['totalParts'], 'finalParts': r['fragments'],
                'discardedCalls': len(retries), 'discardedSeconds': sum(x['seconds'] for x in retries),
                'thermalBefore': r['thermalBefore'], 'thermalAfter': r['thermalAfter'],
                'outputSHA256': hashlib.sha256(text.encode()).hexdigest()})
        item[device] = {'runs': measurements,
                        'meanSeconds': statistics.mean(r['seconds'] for r in runs) if runs else None,
                        'repeatIdentical': runs[0]['translation'] == runs[1]['translation'] if len(runs) == 2 else None}
    item['allAvailableOutputsIdentical'] = len(set(outputs)) == 1
    item['availableOutputCount'] = len(outputs)
    item['crossDeviceIdentical'] = len(set(outputs)) == 1 if item['ios']['runs'] and item['mac']['runs'] else None
    item['iPhoneToMacTimeRatio'] = item['ios']['meanSeconds'] / item['mac']['meanSeconds'] if item['ios']['runs'] and item['mac']['runs'] else None
    rows.append(item)
(a.output / 'summary.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
lines = ['| Article | Chars | Mac pass 1 / 2 (s) | iPhone pass 1 / 2 (s) | iPhone/Mac mean | Parts Mac / iPhone | Retries | Identical outputs |',
         '|---|---:|---:|---:|---:|---|---:|---|']
for r in rows:
    times = [' / '.join(f"{x['seconds']:.1f}" for x in r[d]['runs']) or '—' for d in ['mac', 'ios']]
    parts = ['; '.join(f"{x['initialParts']}→{x['finalParts']}" for x in r[d]['runs']) or '—' for d in ['mac', 'ios']]
    retry = sum(x['discardedCalls'] for d in ['mac', 'ios'] for x in r[d]['runs'])
    ratio = f"{r['iPhoneToMacTimeRatio']:.2f}×" if r['iPhoneToMacTimeRatio'] is not None else '—'
    lines.append(f"| [{r['id']}]({r['url']}) | {r['characters']} | {times[0]} | {times[1]} | {ratio} | {parts[0]} / {parts[1]} | {retry} | {r['crossDeviceIdentical']} |")
(a.output / 'results-table.md').write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
