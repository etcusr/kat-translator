#!/usr/bin/env python3
"""Timing/repeat diagnostics only; semantic acceptance remains an explicit review."""
import argparse
import hashlib
import json
from pathlib import Path
from statistics import median


def summarize(corpus, report):
    cases = []
    for case in corpus["cases"]:
        item = dict(id=case["id"], title=case["title"], kind=case["kind"],
                    quoted=case["quoted"], source_characters=sum(map(len, case["blocks"])), modes={})
        for mode in ["plain", "focused_terms"]:
            rows = [r for r in report["results"] if r["case_id"] == case["id"]
                    and r["mode"] == mode and r["phase"] == "warm"]
            good = [r for r in rows if r["ok"]]
            entry = dict(attempts=len(rows), succeeded=len(good),
                         errors=[r["error"] for r in rows if not r["ok"]])
            if good:
                for field in ["seconds", "first_body_part_seconds", "glossary_seconds"]:
                    values = [r[field] for r in good]
                    entry[field] = dict(median=median(values), min=min(values), max=max(values))
                entry["output_sha256"] = sorted(set(hashlib.sha256(r["output"].encode()).hexdigest() for r in good))
                entry["unique_glossaries"] = len(set(json.dumps((r.get("glossary") or {}).get("terms", []), sort_keys=True, ensure_ascii=False) for r in good))
                entry["terms"] = (good[-1].get("glossary") or {}).get("terms", [])
            item["modes"][mode] = entry
        cases.append(item)
    return dict(complete=report["complete"], frozen=report["frozen"],
                load_seconds=report["load_seconds"], planner_parity=report["planner_parity"],
                warmup_attempts=sum(r["phase"]=="warmup" for r in report["results"]),
                measured_attempts=sum(r["phase"]=="warm" for r in report["results"]), cases=cases)


def comparison(corpus, report):
    lines = ["# Новые тексты: обычный режим и быстрый расширенный словарь",
             "", "Синтетические RU→EN примеры. Показан последний успешный измеренный повтор; ошибки перечислены явно. Это материалы для ручной оценки, а не автоматическая оценка качества.", ""]
    for case in corpus["cases"]:
        lines += [f"## {case['title']}", "", "### Исходник", "", "\n\n".join(case["blocks"]),
                  "", "### Критерии, зафиксированные до измерений", ""]
        lines += [f"- {check}" for check in case["checks"]]
        for mode, name in [("plain", "Обычный режим"), ("focused_terms", "Быстрый расширенный словарь")]:
            rows = [r for r in report["results"] if r["case_id"]==case["id"] and r["mode"]==mode and r["phase"]=="warm"]
            lines += ["", f"### {name}", ""]
            for row in rows:
                if not row["ok"]:
                    lines += [f"Повтор {row['repeat']}: ошибка — {row['error']}", ""]
            good = [r for r in rows if r["ok"]]
            if good:
                row = good[-1]
                lines += [f"Первая содержательная часть {row['first_body_part_seconds']:.2f} с; весь текст {row['seconds']:.2f} с; подготовка {row['glossary_seconds']:.2f} с (включена).", "", row["output"], ""]
                terms = (row.get("glossary") or {}).get("terms", [])
                if terms:
                    lines += ["Термины:", ""]
                    lines += [f"- {t['source']} → {t['target']}" for t in terms]
    return "\n".join(lines)+"\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--corpus", type=Path, default=Path(__file__).with_name("corpus.json"))
    p.add_argument("--results", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    corpus, report = json.loads(a.corpus.read_text()), json.loads(a.results.read_text())
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out/"summary.json").write_text(json.dumps(summarize(corpus, report), ensure_ascii=False, indent=2)+"\n")
    (a.out/"comparison.ru.md").write_text(comparison(corpus, report))


if __name__ == "__main__":
    main()
