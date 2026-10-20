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
Manual input/output is not saved. Kat starts a fresh worker on each click;
the interface reports model loading separately from inference.

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

`--probe-kat OUTPUT.json` on the app checks both Kat worker bridges with one
bundled synthetic context example. Standalone `kat_runner.py index2b` or
`index9b` accepts one sample object on stdin and returns JSON on stdout.

The first pass is separate from three repeated warm passes. Do not describe
the first pass as a cold OS/model-cache test. All latency outliers remain in
the summary. These are translation measurements, not microphone, OCR, TTS,
device-wide network, thermal endurance or production UI acceptance tests.

[Recorded results and quality inspection](../../../docs/benchmarks/mac-system-translation-2026-10-20/README.md).
