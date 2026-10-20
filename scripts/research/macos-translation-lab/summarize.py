#!/usr/bin/env python3
"""Summarize complete successful runs; never silently omit failed measurements."""
import argparse
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
args = parser.parse_args()
rows = json.loads((args.directory / "apple.json").read_text())
loads = {}
for name in ("index2b", "index9b"):
    data = json.loads((args.directory / (name + ".json")).read_text())
    rows.extend(data["results"])
    loads[name] = data["load_seconds"]

summary = {}
for engine in dict.fromkeys(row["engine"] for row in rows):
    selected = [row for row in rows if row["engine"] == engine]
    if len(selected) != 64 or any(row.get("error") or row.get("code", 0) != 0 or not row["output"] for row in selected):
        raise SystemExit(f"Incomplete or unsuccessful run: {engine}")
    if len({(row["id"], row["pass"]) for row in selected}) != 64:
        raise SystemExit(f"Duplicate measurements: {engine}")
    result = {"requests": len(selected), "explicit_load_seconds": loads.get(engine)}
    for phase in ("first_pass", "warm"):
        result[phase] = {}
        for kind in ("all", "short", "context", "paragraph"):
            group = [row["seconds"] for row in selected if row["phase"] == phase and (kind == "all" or row["kind"] == kind)]
            result[phase][kind] = dict(n=len(group), median_seconds=statistics.median(group),
                                      min_seconds=min(group), max_seconds=max(group))
    summary[engine] = result
(args.directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
for engine, result in summary.items():
    print(engine, "load", result["explicit_load_seconds"], "warm", result["warm"])
