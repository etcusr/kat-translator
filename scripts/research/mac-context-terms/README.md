# Context and terminology Mac experiment

**English** | [Русский](README.ru.md)

A separate local **Kat Context Lab** for RU→EN with the existing Index 9B MLX/MTP2 runtime and weights. It never replaces Kat, writes Kat settings/history, or uploads builds. Requires this workspace, the existing research Python environment/model installation and macOS 27 on Apple Silicon. The generated app embeds the explicitly supplied private fixture and comparison results and must not be distributed.

Seven isolated modes use identical production 128-token chunk boundaries:

- `plain`: current production prompt, each piece independent.
- `context`: previous source piece and its actual translation as one preceding chat turn. This survives OCR paragraph boundaries but is not the whole document.
- `context_terms`: the previous pair plus relevant entries from a fixed document glossary.
- `terms`: the same glossary without the previous turn, to isolate the glossary's contribution.
- `auto_terms`: extract up to ten terms from the complete source with the same resident model, then translate using relevant terms without the previous turn. No manual glossary is read in this mode.
- `fast_terms`: use pymorphy3 to group repeated quoted Russian expressions (or repeated nouns if none); select at most four, retain the opening two sentences and local neighboring sentences, and ask the same model for only their English translations as a JSON string array. No manual glossary is read. This intentionally covers fewer terms.
- `focused_terms`: supplement that shortlist with other repeated common nouns, up to ten entries in total. Supplementary nouns reuse the same selected context; named/geographic terms and abbreviations are excluded from this supplementary pass. This adds coverage with a slightly longer answer.

The glossary in `terms` and `context_terms` is hand-prepared, editable JSON with `source`, `aliases` and `target` fields. Case-insensitive aliases select relevant entries per piece; inflected forms require appropriate aliases. It is supplied as a prompt instruction, not forced decoding or output substitution. The model can ignore it or obey a wrong glossary. Semantic consistency is not guaranteed. Previous context resets for every document. Prompts over 1,024 tokens fail explicitly; no silent fallback. Native limits remain unchanged.

Automatic extraction uses a separate source-only prompt and JSON validation. Source entries must occur in the document (case/е–ё variants allowed); unattested entries are dropped. A conservative suffix heuristic groups observed single-word Russian inflections; it is not a full morphological analyzer. Matching uses word boundaries. Conflicting entries, malformed output, an empty accepted glossary or an extraction prompt over 1,024 tokens fail explicitly without manual fallback or truncation. English target correctness is not validated. The glossary is regenerated for every request, with no cross-document cache. Extraction time is included in total and first-piece latency. Manual preparation time is not measured.

The fast selector retains only observed source aliases and keeps its per-word parse cache within one document. Its morphology dictionaries are reused. If no candidates are found, it explicitly returns an empty glossary and translates normally without a model prepass. Invalid outputs/counts or an over-budget selected context raise an error; there is no hidden full-glossary fallback. Target correctness and broad semantic consistency remain unverified. All selection and translation-prepass time is included in timings.

The UI displays completed pieces and a global character progress bar, has cancellation/unload, and keeps a worker for up to five idle minutes. Cancellation terminates this lab's worker; the next request loads it again. Closing the window also stops the worker. Loading is separate from translation timings. Saved comparison results shown at startup are labeled; pressing Translate performs a fresh request. Other modes' displayed results are snapshots of their last runs and are not refreshed by editing the input.

## Run

For the optional fast mode, install the pinned CPU dependencies into the isolated research directory (not the app runtime):

```sh
.build/mac-index-mlx-mtp/venv/bin/python -m pip install \
  --target .build/mac-fast-terms-2026-10-20/libraries \
  -r scripts/research/mac-context-terms/requirements-fast.txt
```

Prepare private JSON: `{"blocks": ["Title", "First paragraph", "Second paragraph"], "glossary": [...]}`. For an image, use the same recognized blocks as production. Do not commit private source/output.

```sh
python3 scripts/research/mac-context-terms/build.py --fixture /absolute/private/fixture.json
.build/mac-index-mlx-mtp/venv/bin/python scripts/research/mac-context-terms/runner.py \
  --fixture /absolute/private/fixture.json --output /absolute/private/results.json \
  --modes plain,auto_terms,focused_terms --repeats 3 --swift-planner .build/mac-context-terms-2026-10-20/planner
python3 scripts/research/mac-context-terms/build.py \
  --fixture /absolute/private/fixture.json --comparison /absolute/private/results.json
open '.build/mac-context-terms-2026-10-20/Kat Context Lab.app'
```

The parity probe calls the production Swift planner with the same tokenizer and asserts exact piece equality. Each benchmark has a separately labeled full warm-up pass, then rotated mode orders for repeated warm passes, one resident model and a fresh generator per piece. Measure first token, first completed piece, first non-title piece and full elapsed inference-side request time. These exclude OCR/UI rendering/TTS and model initialization. On the article fixture, the first block is a short title, so first non-title piece is the useful responsiveness measure. No independent quality grading or broad-language claims.

`test_fast_glossary.py` checks actual morphology, context retention, document isolation, empty selection, budgets, output validation and no manual seeding. `test_auto_glossary.py` checks source attestation, inflections, invalid/conflicting entries, budgets, no manual seeding and per-request regeneration. `test_runner.py` checks source coverage, prompt isolation, relevant glossary selection and document reset. `--probe OUTPUT.json` on the app performs a real context+terms request through its worker bridge, writes private output and exits. Add `--auto` for a real full-glossary request `--fast` for the narrow selector or `--focused` for the expanded selector. Each mode displays its own generated glossary. `summarize.py --modes plain,auto_terms,focused_terms` strips private text from timing/hash evidence; its number/term checks are article-specific diagnostics, not a general quality score.

[Experiment results](../../../docs/benchmarks/mac-context-terms-2026-10-20/README.md).

[Automatic glossary comparison](../../../docs/benchmarks/mac-auto-terms-2026-10-20/README.md).

[Accelerated glossary comparison](../../../docs/benchmarks/mac-fast-terms-2026-10-20/README.md).

## Frozen multi-document comparison

`corpus.json` contains eight new synthetic RU→EN documents (1,512–1,651 characters): five long texts and three dialogues, seven without quoted terminology. One dialogue deliberately mixes invoice/account/score and physical key/musical clef meanings. It is a stress case, not a frequency-representative sample. Each case includes a title and five semantic review criteria fixed before inference; no manual glossary or target translation is sent to the model.

`corpus_runner.py --frozen HASHES.json --output RESULTS.json --swift-planner PATH --repeats 2` checks corpus and `fast_glossary.py` SHA-256 values against the supplied frozen record, checks production planner parity for every case, warms both modes on every document, then alternates paired mode order and rotates case order. Only `plain` and the existing, unchanged `focused_terms` are tested. Failures retain elapsed time and partial events; there is no retry/fallback. `corpus_summary.py --results RESULTS.json --out DIRECTORY` reports timing, failures and repeat hashes, and renders full synthetic comparisons. It does not assign semantic quality scores. Warmup and failed requests are excluded from successful latency medians and counted separately.

Build with `--corpus scripts/research/mac-context-terms/corpus.json --comparison RESULTS.json` in addition to `--fixture FIRST_CASE.json` to show a case selector with saved, measured results in the separate Mac app. Selecting a case clears previous text/terms/metrics before loading that case. App probes accept `--case CASE_ID` and `--plain` or `--focused`. The file-based probe verifies the built app/worker bridge, not visual or mouse interaction acceptance. New inputs can still be edited; switching cases discards edits.

[New-text and dialogue evaluation](../../../docs/benchmarks/mac-glossary-corpus-2026-10-20/README.md).

CLI probes start independently of window restoration and write explicit startup/error/completion states. A completed probe records the selected case and visible window count; zero visible windows is not visual UI acceptance.
