# Mac translation experiment

**English** | [Русский](README.ru.md)

A separate local **Kat Translation Lab** application compares Apple Translation
with Kat's Index 2B and Index 9B MLX + MTP2 engines. It does not replace the
installed app, modify its settings/history, or produce a Store release.

Requires this workspace and its existing model/runtime dependencies, Apple
Silicon, Xcode and macOS 27+. This is a local developer build, not a portable
distribution. The workspace path is embedded in an ignored bundle resource;
no weights are copied into the application.

```sh
python3 scripts/research/macos-translation-lab/build.py
open ".build/mac-system-translation-2026-10-20/Kat Translation Lab.app"
```

Select a backend and RU→EN or EN→RU, enter a phrase or choose an example,
then press Translate. Context should be included in the source paragraph;
the experiment translates the entire paragraph, not just its last sentence.
Manual input/output is not saved. Kat keeps one worker/model for subsequent
requests and unloads it after 5 minutes idle by default, on backend change, Stop, window
close or Unload Kat. Each request still starts a fresh translation context.
The interface reports model loading separately from inference; reused loads
are zero. The first request still pays initialization cost.
Settings allows 1–60 minutes (including 5 and 10), persisted across launches.
Changing the timer updates the loaded worker without reloading; during a
translation the update waits until the request finishes.

Apple uses an installed-language session. If models are unavailable, use
Prepare Apple Languages for the selected direction/strategy and complete
any system download confirmation. `highFidelity` is a **preference** and can
fall back to traditional models; the selected option does not prove that
Apple Intelligence weights were used. Network connectivity was not physically
disabled in the recorded experiment.

## Repeat the synthetic comparison

Run sequentially to avoid contention. The Apple application must stay open
until its status reports completion. Quit it before starting another instance.
The benchmark writes only the bundled synthetic fixtures, not user-entered text.

```sh
open -n ".build/mac-system-translation-2026-10-20/Kat Translation Lab.app" --args \
  --benchmark "$PWD/.build/mac-system-translation-2026-10-20/apple.json"
.build/mac-index-mlx-mtp/venv/bin/python scripts/research/macos-translation-lab/kat_runner.py \
  index2b --fixtures tests/fixtures/mac-system-translation.json \
  --output .build/mac-system-translation-2026-10-20/index2b.json
.build/mac-index-mlx-mtp/venv/bin/python scripts/research/macos-translation-lab/kat_runner.py \
  index9b --fixtures tests/fixtures/mac-system-translation.json \
  --output .build/mac-system-translation-2026-10-20/index9b.json
python3 scripts/research/macos-translation-lab/summarize.py \
  .build/mac-system-translation-2026-10-20
```

`--probe-kat OUTPUT.json` on the app checks both Kat worker bridges and a repeated
9B request with one bundled synthetic context example. Standalone `kat_runner.py index2b` or
`index9b` accepts one sample object on stdin and returns JSON on stdout.

The first pass is separate from three repeated warm passes. Do not describe
the first pass as a cold OS/model-cache test. All latency outliers remain in
the summary. These are translation measurements, not microphone, OCR, TTS,
device-wide network, thermal endurance or production UI acceptance tests.

[Recorded results and quality inspection](../../../docs/benchmarks/mac-system-translation-2026-10-20/README.md).

## Latency diagnosis and resident-worker check

```sh
python3 scripts/research/macos-translation-lab/test_worker.py
.build/mac-index-mlx-mtp/venv/bin/python scripts/research/macos-translation-lab/profile_mlx.py \
  .build/mac-mlx-profile.json
```

Both commands use real models and Metal; run them sequentially. The opt-in
regression checks 32 unchanged translations, worker reuse, invalid-input
recovery and clean EOF. The profiler separates generator stages, CPU/wall
time, GC, MLX allocations and process page faults. It does not use a timer
for stack sampling. Historical 12-second outliers were not reproduced in
192 fresh control requests and remain unexplained. The resident worker
removes repeated loading in the test UI; it is not a fix for those historical
inference outliers. [Evidence](../../../docs/benchmarks/mac-mlx-latency-2026-10-20/README.md).

## Experimental long-text splitting (Index 9B only)

The Index 9B view offers Whole (default), Chunks, and Chunks with Context.
The examples menu also contains 16 long/context fixtures and two boundary-context probes. Chunks target
128 source tokens and prefer sentence/line boundaries, with a word/character
fallback for oversized sentences. Source spans cover the entire input.
Context mode translates up to 64 preceding and 32 following source tokens
alongside the current part, retaining explicit boundary markers. Only the
translation between the two unique ordered markers is displayed; a malformed
boundary returns an error rather than accepting an ambiguous result.
This is a bounded context window, not guaranteed preservation of remote facts.

Each completed part appears immediately with an incomplete-result status.
Stop terminates the worker; a stopped/failed partial output is not a completed
translation. No automatic mode switching or cross-request dialogue memory.
Splitting may improve first-result latency and avoid token-limit failures,
but can increase total time or alter meaning. Both chunk modes remain explicit
experiments; compare the output before using it.

```sh
python3 scripts/research/macos-translation-lab/test_chunking.py
python3 scripts/research/macos-translation-lab/compare_chunks.py .build/mac-chunks/results.json
python3 scripts/research/macos-translation-lab/summarize_chunks.py .build/mac-chunks/results.json .build/mac-chunks/report
```

`--probe-chunks OUTPUT.json` on the app checks a bundled long example in
whole/context modes through the actual Swift worker bridge, including progress
messages. [Comparison and limits](../../../docs/benchmarks/mac-chunk-context-2026-10-20/README.md).
