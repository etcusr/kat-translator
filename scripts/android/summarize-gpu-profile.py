#!/usr/bin/env python3
"""Summarize opt-in Kat wall stages and Vulkan timestamp tables (milliseconds).

Timestamp profiling serializes GPU work and perturbs end-to-end latency.
Keep individual dispatch tables: split/prefix prefill is not one table.
"""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


def summarize(log):
    requests = []
    for block in log.split("KAT_PROFILE_BEGIN\n")[1:]:
        stages = {}
        for name, ms, count in re.findall(r"KAT_STAGE (\S+) ([\d.]+) ms (\d+) calls", block):
            stages[name] = {"ms": float(ms), "calls": int(count)}
        dispatches = []
        for table in block.split("Vulkan Timings:\n")[1:]:
            ops = defaultdict(float)
            for name, count, average, total in re.findall(r"^(.+): (\d+) x ([\d.e+]+) us = ([\d.e+]+) us", table, re.M):
                ops[name] += float(total) / 1000
            dispatches.append({"totalMs": sum(ops.values()), "ops": dict(sorted(ops.items(), key=lambda x: -x[1]))})
        requests.append({"complete": "KAT_PROFILE_END" in block, "wallStages": stages, "dispatches": dispatches})
    if not requests:
        raise ValueError("No KAT_PROFILE_BEGIN markers found")
    return {"warning": "GPU timestamp profiling perturbs latency; use unprofiled report.json for speed comparisons.", "requests": requests}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.log.read_text()), indent=2, ensure_ascii=False))
