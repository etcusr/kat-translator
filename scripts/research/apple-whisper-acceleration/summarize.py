"""Publish timing/quality metrics without copying private audio or transcripts."""
import argparse
import json
import re
import statistics
from pathlib import Path


def words(text):
    return re.findall(r"\w+", text.lower(), flags=re.UNICODE)


def edits(a, b):
    previous = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        current = [i]
        for j, y in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1,
                               previous[j - 1] + (x != y)))
        previous = current
    return previous[-1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("work", type=Path)
    p.add_argument("output", type=Path)
    a = p.parse_args()
    groups = {
        **{f"mac-{x}": [f"mac-{x}", f"mac-{x}-b"]
           for x in ["f16", "q8", "coreml", "coreml-q8", "mlx"]},
        "mac-coreml-ne": ["mac-coreml-ne"],
        **{f"ios-{x}": [f"ios-{x}-matched", f"ios-{x}-matched-b", f"ios-{x}-matched-c"]
           for x in ["f16", "q8", "coreml", "coreml-q8", "mlx", "mlx-fp16", "coreml-ne"]},
        "ios-f16-initial": ["ios-f16", "ios-f16-b"],
        "ios-q8-initial": ["ios-q8", "ios-q8-b"],
        "ios-coreml-initial": ["ios-coreml"],
        "ios-mlx-initial": ["ios-mlx"],
    }
    baselines = {}
    for platform in ["mac", "ios"]:
        data = json.loads((a.work / f"{platform}-f16.json").read_text())
        baselines[platform] = {r["id"]: r["text"].strip() for r in data["rows"]}
    jfk = words("And so my fellow Americans ask not what your country can do for you ask what you can do for your country")
    result = {"groups": {}, "qualityMeaning": "Private: agreement with F16, not WER. JFK: known reference WER.",
              "memoryMeaning": "Max sampled physical footprint, not continuous peak. MLX allocation peak and peak RSS are separate metrics."}
    for group, names in groups.items():
        reports = []
        for name in names:
            path = a.work / (name + ".json")
            if path.exists():
                report = json.loads(path.read_text())
                if not report.get("completed"):
                    raise RuntimeError(f"Incomplete run: {name}")
                reports.append((name, report))
        if not reports:
            continue
        rows = [r for _, report in reports for r in report["rows"] if not r["warmup"]]
        all_count = len(rows)
        # Core ML's first device compilation warms the phone. Compare like thermal states.
        if group.startswith("ios-") and not group.endswith("-initial"):
            rows = [r for r in rows if r["thermalBefore"] == 1 and r["thermalAfter"] == 1]
        summary = {"runs": [name for name, _ in reports],
                   "loadSeconds": [r["loadSeconds"] for _, r in reports],
                   "excludedThermalRows": all_count - len(rows), "cases": {}}
        for case in ["private-short", "private-long", "jfk"]:
            sample = [r for r in rows if r["id"] == case]
            if not sample:
                raise RuntimeError(f"No thermally matched samples for {group}/{case}")
            times = [r["seconds"] for r in sample]
            baseline = baselines[group.split("-")[0]][case]
            texts = [r["text"].strip() for r in sample]
            entry = {
                "n": len(times), "seconds": times, "medianSeconds": statistics.median(times),
                "minSeconds": min(times), "maxSeconds": max(times),
                "audioSeconds": sample[0]["audioSeconds"],
                "exactAgreementWithF16": sum(t == baseline for t in texts),
                "normalizedEditsFromF16": [edits(words(baseline), words(t)) for t in texts],
                "thermalStates": sorted({(r["thermalBefore"], r["thermalAfter"]) for r in sample if "thermalBefore" in r}),
                "maxSampledFootprintBytes": max(r.get("memory", {}).get("footprint", 0) for r in sample),
                "maxMLXAllocatedBytes": max(r.get("mlxPeak", 0) for r in sample),
                "peakRSSBytes": max(r.get("peakRSS", 0) for r in sample),
                "uniqueTranscripts": len(set(texts)),
            }
            if case == "jfk":
                entry["referenceWords"] = len(jfk)
                entry["wordErrors"] = [edits(jfk, words(t)) for t in texts]
            summary["cases"][case] = entry
        result["groups"][group] = summary
    result["excludedRuns"] = [{"run": "ios-coreml-cool", "reason": "Nominal thermal state not reached within 300 seconds; no inference results."}]
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
