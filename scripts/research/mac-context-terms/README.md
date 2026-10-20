# Context and terminology Mac experiment

**English** | [Русский](README.ru.md)

A separate local **Kat Context Lab** for RU→EN with the existing Index 9B MLX/MTP2 runtime and weights. It never replaces Kat, writes Kat settings/history, or uploads builds. Requires this workspace, the existing research Python environment/model installation and macOS 27 on Apple Silicon. The generated app embeds the explicitly supplied private fixture and comparison results and must not be distributed.

Five isolated modes use identical production 128-token chunk boundaries:

- `plain`: current production prompt, each piece independent.
- `context`: previous source piece and its actual translation as one preceding chat turn. This survives OCR paragraph boundaries but is not the whole document.
- `context_terms`: the previous pair plus relevant entries from a fixed document glossary.
- `terms`: the same glossary without the previous turn, to isolate the glossary's contribution.
- `auto_terms`: extract up to ten terms from the complete source with the same resident model, then translate using relevant terms without the previous turn. No manual glossary is read in this mode.

The glossary in `terms` and `context_terms` is hand-prepared, editable JSON with `source`, `aliases` and `target` fields. Case-insensitive aliases select relevant entries per piece; inflected forms require appropriate aliases. It is supplied as a prompt instruction, not forced decoding or output substitution. The model can ignore it or obey a wrong glossary. Semantic consistency is not guaranteed. Previous context resets for every document. Prompts over 1,024 tokens fail explicitly; no silent fallback. Native limits remain unchanged.

Automatic extraction uses a separate source-only prompt and JSON validation. Source entries must occur in the document (case/е–ё variants allowed); unattested entries are dropped. A conservative suffix heuristic groups observed single-word Russian inflections; it is not a full morphological analyzer. Matching uses word boundaries. Conflicting entries, malformed output, an empty accepted glossary or an extraction prompt over 1,024 tokens fail explicitly without manual fallback or truncation. English target correctness is not validated. The glossary is regenerated for every request, with no cross-document cache. Extraction time is included in total and first-piece latency. Manual preparation time is not measured.

The UI displays completed pieces and a global character progress bar, has cancellation/unload, and keeps a worker for up to five idle minutes. Cancellation terminates this lab's worker; the next request loads it again. Closing the window also stops the worker. Loading is separate from translation timings. Saved comparison results shown at startup are labeled; pressing Translate performs a fresh request. Other modes' displayed results are snapshots of their last runs and are not refreshed by editing the input.

## Run

Prepare private JSON: `{"blocks": ["Title", "First paragraph", "Second paragraph"], "glossary": [...]}`. For an image, use the same recognized blocks as production. Do not commit private source/output.

```sh
python3 scripts/research/mac-context-terms/build.py --fixture /absolute/private/fixture.json
.build/mac-index-mlx-mtp/venv/bin/python scripts/research/mac-context-terms/runner.py \
  --fixture /absolute/private/fixture.json --output /absolute/private/results.json \
  --modes plain,terms,auto_terms --repeats 3 --swift-planner .build/mac-context-terms-2026-10-20/planner
python3 scripts/research/mac-context-terms/build.py \
  --fixture /absolute/private/fixture.json --comparison /absolute/private/results.json
open '.build/mac-context-terms-2026-10-20/Kat Context Lab.app'
```

The parity probe calls the production Swift planner with the same tokenizer and asserts exact piece equality. Each benchmark has a separately labeled full warm-up pass, then rotated mode orders for repeated warm passes, one resident model and a fresh generator per piece. Measure first token, first completed piece, first non-title piece and full elapsed inference-side request time. These exclude OCR/UI rendering/TTS and model initialization. On the article fixture, the first block is a short title, so first non-title piece is the useful responsiveness measure. No independent quality grading or broad-language claims.

`test_auto_glossary.py` checks source attestation, inflections, invalid/conflicting entries, budgets, no manual seeding and per-request regeneration. `test_runner.py` checks source coverage, prompt isolation, relevant glossary selection and document reset. `--probe OUTPUT.json` on the app performs a real context+terms request through its worker bridge, writes private output and exits. Add `--auto` to the app probe for a real automatic-glossary request. `summarize.py --modes plain,terms,auto_terms` strips private text from timing/hash evidence; its number/term checks are article-specific diagnostics, not a general quality score.

[Experiment results](../../../docs/benchmarks/mac-context-terms-2026-10-20/README.md).

[Automatic glossary comparison](../../../docs/benchmarks/mac-auto-terms-2026-10-20/README.md).
