# Context and terminology Mac experiment

**English** | [Русский](README.ru.md)

A separate local **Kat Context Lab** for RU→EN with the existing Index 9B MLX/MTP2 runtime and weights. It never replaces Kat, writes Kat settings/history, or uploads builds. Requires this workspace, the existing research Python environment/model installation and macOS 27 on Apple Silicon. The generated app embeds the explicitly supplied private fixture and comparison results and must not be distributed.

Four isolated modes use identical production 128-token chunk boundaries:

- `plain`: current production prompt, each piece independent.
- `context`: previous source piece and its actual translation as one preceding chat turn. This survives OCR paragraph boundaries but is not the whole document.
- `context_terms`: the previous pair plus relevant entries from a fixed document glossary.
- `terms`: the same glossary without the previous turn, to isolate the glossary's contribution.

The glossary is hand-prepared, editable JSON with `source`, `aliases` and `target` fields. Case-insensitive aliases select relevant entries per piece; inflected forms require appropriate aliases. It is supplied as a prompt instruction, not forced decoding or output substitution. The model can ignore it or obey a wrong glossary. No automatic extraction or guaranteed semantic consistency is implemented. Previous context resets for every document. Prompts over 1,024 tokens fail explicitly; no silent fallback. Native limits remain unchanged.

The UI displays completed pieces and a global character progress bar, has cancellation/unload, and keeps a worker for up to five idle minutes. Cancellation terminates this lab's worker; the next request loads it again. Closing the window also stops the worker. Loading is separate from translation timings. Saved comparison results shown at startup are labeled; pressing Translate performs a fresh request. Other modes' displayed results are snapshots of their last runs and are not refreshed by editing the input.

## Run

Prepare private JSON: `{"blocks": ["Title", "First paragraph", "Second paragraph"], "glossary": [...]}`. For an image, use the same recognized blocks as production. Do not commit private source/output.

```sh
python3 scripts/research/mac-context-terms/build.py --fixture /absolute/private/fixture.json
.build/mac-index-mlx-mtp/venv/bin/python scripts/research/mac-context-terms/runner.py \
  --fixture /absolute/private/fixture.json --output /absolute/private/results.json \
  --repeats 3 --swift-planner .build/mac-context-terms-2026-10-20/planner
python3 scripts/research/mac-context-terms/build.py \
  --fixture /absolute/private/fixture.json --comparison /absolute/private/results.json
open '.build/mac-context-terms-2026-10-20/Kat Context Lab.app'
```

The parity probe calls the production Swift planner with the same tokenizer and asserts exact piece equality. Each benchmark has a separately labeled full warm-up pass, then rotated mode orders for repeated warm passes, one resident model and a fresh generator per piece. Measure first token, first completed piece, first non-title piece and full elapsed inference-side request time. These exclude OCR/UI rendering/TTS and model initialization. On the article fixture, the first block is a short title, so first non-title piece is the useful responsiveness measure. No independent quality grading or broad-language claims.

`test_runner.py` checks source coverage, prompt isolation, relevant glossary selection and document reset. `--probe OUTPUT.json` on the app performs a real context+terms request through its worker bridge, writes private output and exits. `summarize.py` strips private text from timing/hash evidence; its number/term checks are article-specific diagnostics, not a general quality score.

[Experiment results](../../../docs/benchmarks/mac-context-terms-2026-10-20/README.md).
