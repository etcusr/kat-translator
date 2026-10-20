"""Publish numeric file-input results and equality checks, never private text."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("work", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
cases = ["original-date", "time-before-date", "date-before-time", "long-recording"]
raw, outputs = {}, {}
reference_hashes = None
for variant in ["f16", "q8", "coreml-q8"]:
    name = "files-" + variant
    rows = [json.loads(x) for x in (a.work / (name + "-voice-lab.jsonl")).read_text().splitlines()]
    assert rows[0]["variant"] == variant
    assert rows[0]["automaticSpeech"] is False
    assert any(r["phase"] == "asr.load.end" for r in rows)
    assert all(r["baseline"] == (variant == "f16") for r in rows if r["phase"] == "asr.load.begin")
    assert "** TEST EXECUTE SUCCEEDED **" in (a.work / (name + ".log")).read_text()
    cycles = [r for r in rows if r["phase"] == "cycle.finished"]
    decoded = [r for r in rows if r["phase"] == "file.decoded"]
    assert len(cycles) == len(decoded) == 8
    assert not any(r["phase"] == "capture.started" for r in rows)
    assert not any(r["phase"] == "playback.started" for r in rows)
    hashes = [r["pcmSHA256"] for r in decoded]
    assert hashes[:4] == hashes[4:]
    assert len(set(hashes[:4])) == 4
    if reference_hashes is None:
        reference_hashes = hashes
    assert hashes == reference_hashes, "Different decoded PCM invalidates matched comparison"
    assert all(c["ready"] and c["voiceReady"] and not c["error"] and c["metric"]["status"] == "completed"
               and c["metric"]["inputMode"] == "audio-file" for c in cycles)
    assert all(c["metric"]["ttsSeconds"] == c["metric"]["spokenSeconds"] == c["metric"]["ttsFragments"] == 0
               for c in cycles)
    load_seconds, load_start = [], None
    for row in rows:
        if row["phase"] == "asr.load.begin":
            load_start = row["uptime"]
        elif row["phase"] == "asr.load.end":
            assert row["success"] and load_start is not None
            load_seconds.append(row["uptime"] - load_start)
            load_start = None
    raw[variant] = cycles
    outputs[variant] = {
        "completedFileCycles": len(cycles),
        "microphoneCapture": False,
        "automaticSpeech": False,
        "dateTimeRepair": False,
        "memorySaving": False,
        "maximumSampledFootprintBytes": max(r["footprintBytes"] for r in rows),
        "maximumSampledResidentBytes": max(r["residentBytes"] for r in rows),
        "minimumProcessAllocationHeadroomBytes": min(r["availableBytes"] for r in rows),
        "memoryWarnings": sum(r["phase"] == "memory.warning" for r in rows),
        "asrLoads": sum(r["phase"] == "asr.load.end" for r in rows),
        "asrLoadSeconds": load_seconds,
        "thermalStatesAcrossTrace": sorted(set(r["thermal"] for r in rows)),
        "manualRecognitionPreparations": (a.work / (name + ".log")).read_text().count("VOICE_LAB_MANUAL_PREPARE_"),
        "playbackCompletions": sum(r["phase"] == "playback.finished" for r in rows),
        "cycles": [
            {"case": cases[i % 4], "pass": i // 4 + 1, "decodedAudio": {k: d[k] for k in ["pcmSHA256", "samples", "seconds"]},
             "metric": c["metric"], "readyAfterCycle": c["ready"],
             "sameSourceAsFirstPass": c["source"] == cycles[i % 4]["source"],
             "sameTranslationAsFirstPass": c["translation"] == cycles[i % 4]["translation"]}
            for i, (c, d) in enumerate(zip(cycles, decoded))
        ],
    }
for variant in ["q8", "coreml-q8"]:
    outputs[variant]["agreementWithF16NotAccuracy"] = [
        {"case": cases[i % 4], "pass": i // 4 + 1,
         "sourceExact": c["source"] == raw["f16"][i]["source"],
         "translationExact": c["translation"] == raw["f16"][i]["translation"]}
        for i, c in enumerate(raw[variant])
    ]
result = {"scope": "Identical decoded PCM through diagnostic file input; no Mac audio I/O or iPhone microphone capture",
          "runs": outputs, "limitations": [
              "Four files, two passes per variant; second pass is one warm observation per case, not a general benchmark",
              "Device thermal state and process loads are reported; no cross-device claim",
              "TTS is deliberately disabled; earlier full-cycle checks cover playback",
              "File input bypasses live recording preview/VAD and cannot replace microphone acceptance",
          ]}
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print("24 file cycles validated; all four PCM hashes identical across three variants and both passes")
