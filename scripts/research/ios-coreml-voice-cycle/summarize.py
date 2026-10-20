"""Sanitize completed acoustic runs. Never export transcripts or device identifiers."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("work", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
names = ["baseline-a", "coreml-q8-a", "coreml-q8-dates-audible", "baseline-dates-audible"]
raw, summaries = {}, {}
for name in names:
    rows = [json.loads(line) for line in (a.work / (name + "-voice-lab.jsonl")).read_text().splitlines()]
    cycles = [r for r in rows if r["phase"] == "cycle.finished"]
    assert len(cycles) == 4, (name, len(cycles))
    assert rows[0]["baseline"] == name.startswith("baseline"), name
    log = (a.work / (name + ".log")).read_text()
    assert "** TEST EXECUTE SUCCEEDED **" in log and "VOICE_LAB_REPEAT_CAPTURE_OK" in log
    assert all(c["ready"] and c["voiceReady"] and not c["error"] and c["metric"]["status"] == "completed" for c in cycles)
    raw[name] = cycles
    start = rows[0]["uptime"]
    loads = []
    began = None
    for r in rows:
        if r["phase"] == "asr.load.begin":
            began = r["uptime"]
        if r["phase"] == "asr.load.end":
            assert r["success"] and began is not None
            loads.append(r["uptime"] - began)
    summaries[name] = {
        "variant": "native F16" if name.startswith("baseline") else "Core ML FP16 encoder + native Q8",
        "completedCycles": 4,
        "repeatedLiveCapture": True,
        "dateTimeRepair": False,
        "memorySaving": False,
        "sampleIntervalMilliseconds": 100,
        "maximumSampledFootprintBytes": max(r["footprintBytes"] for r in rows),
        "reportedProcessLifetimePeakBytes": max(r["lifetimePeakBytes"] for r in rows),
        "maximumSampledResidentBytes": max(r["residentBytes"] for r in rows),
        "minimumProcessAllocationHeadroomBytes": min(r["availableBytes"] for r in rows),
        "memoryWarnings": sum(r["phase"] == "memory.warning" for r in rows),
        "asrLoadSeconds": loads,
        "events": [
            {"phase": r["phase"], "sinceLaunchSeconds": r["uptime"] - start,
             "footprintBytes": r["footprintBytes"], "availableBytes": r["availableBytes"], "thermal": r["thermal"]}
            for r in rows if r["phase"] in {"memory.warning", "asr.unload", "asr.load.begin", "asr.load.end"}
        ],
        "playbackRoutes": sorted({r["route"] for r in rows if r["phase"] == "playback.started"}),
        "outputVolumes": sorted({r["outputVolume"] for r in rows if r["phase"] == "playback.started"}),
        "cycles": [
            {"index": i, "metric": c["metric"], "readyAfterCycle": c["ready"],
             "voiceReadyAfterCycle": c["voiceReady"], "hasUserMessage": bool(c["message"])}
            for i, c in enumerate(cycles)
        ],
    }
quality = {}
for name, base in [("coreml-q8-a", "baseline-a"), ("coreml-q8-dates-audible", "baseline-dates-audible")]:
    quality[name] = [
        {"index": i, "exactSourceAgreement": c["source"] == b["source"],
         "exactTranslationAgreement": c["translation"] == b["translation"]}
        for i, (c, b) in enumerate(zip(raw[name], raw[base]))
    ]
result = {
    "sourceCommit": json.loads((a.work / "snapshot.json").read_text())["commit"],
    "scope": "Separate iPhone lab; actual microphone capture, Index 9B, Lessac synthesis/playback; no production change",
    "runs": summaries, "baselineAgreementNotAccuracy": quality,
    "excludedRun": {
        "name": "coreml-q8-dates", "completedCycles": 0,
        "reason": "Interrupted after the owner reported low acoustic level; no ASR invocation reached in saved trace",
        "originalMeanDBFS": -40.1, "originalPeakDBFS": -19.6,
        "repeatStimulus": "loudnorm=I=-18:TP=-2:LRA=11; same four normalized inputs for both variants",
    },
}
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print("Sanitized", sum(v["completedCycles"] for v in summaries.values()), "completed live cycles")
