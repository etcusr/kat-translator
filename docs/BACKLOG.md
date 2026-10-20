# Future work

**English** | [Русский](BACKLOG.ru.md)

Deferred tasks, not completed changes or release promises.

## Mac system translation experiment

20 October 2026: [separate test application and measurements](benchmarks/mac-system-translation-2026-10-20/README.md), no production integration.

- [x] Build a separate Mac app with Apple lowLatency/highFidelity and Kat Index 2B/9B; verify both Kat worker bridges.
- [x] Compare 256 synthetic RU↔EN translations, retain startup/outlier data and manually inspect context, times and pronouns.
- [x] Profile 192 fresh 9B control requests and compare unchanged outputs; maximum 2.41 s. [Investigation](benchmarks/mac-mlx-latency-2026-10-20/README.md).
- [x] Remove repeated model loading in the separate Mac Lab using one resident worker, with a saved idle timer (default 5 minutes, Settings 1–60) and 32 matching regression translations.
- [ ] Capture the historical 12.49 s inference outlier with contemporaneous system traces. It did not recur in the fresh controls; root cause remains unconfirmed.
- [ ] Evaluate held-out examples and phone performance before selecting/routing engines. Apple was much faster but made meaning errors; highFidelity did not establish use of a different model.


## Context-aware translation: latency and quality

Research started 20 October 2026; **no production change**. A standalone Mac probe completed 320 synthetic EN→RU translations and 64 memory-generation calls. Short source dialogue improved disambiguation; generating a separate summary before each short translation increased latency and sometimes invented facts. Small-model grammar and fidelity remain limiting. [Method, results and next experiments](benchmarks/context-translation-2026-10-20/README.md).

- [x] Compare current prompts, an instruction-only control, source dialogue, supplied memory and generated memory on the same native backend.
- [x] Include memory-generation cost and manually inspect failure cases rather than equating pattern checks with translation quality.
- [ ] Expand to independent dialogues, RU→EN and other languages; measure first complete sentence, full result, memory and thermal behavior on supported devices.
- [ ] Prototype bounded source-context selection with explicit speaker/session boundaries and corrections; evaluate state reuse without changing the translation.
- [ ] Compare any draft/verification approach against existing MTP2, including both models' memory and all inference costs.
- [ ] If compact-model quality remains insufficient, evaluate dialogue-focused distillation/fine-tuning with separate held-out examples.

Context routing, persistent memory, new decoding mechanisms and model training are proposals, not shipped features. Research does not change the builds submitted to App Review.

## Image translation: completeness, layout and speed

Recorded 18 October 2026. **Deferred at the owner's request; no implementation started.**

The supplied Mac screenshots show two separate posts translated from Russian to English with Index-Translate 9B / MLX + MTP2. Some source lines are absent from the translated text; sentences become disconnected fragments. The right pane has excessive gaps and includes repeated channel headings and service metadata. In the exported image, some original lines remain untranslated, source text shows through overlays, and text sizes and coverage are inconsistent. The exact stage causing each omission is not yet established.

The displayed timings are OCR **33.17 s**, translation **12.14 s**, total **45.31 s**. These are observations from the owner's screenshot, not a new controlled benchmark.

Future investigation and acceptance:

- Trace OCR coverage, reading order, paragraph grouping, translation and export separately; establish where lines disappear.
- Preserve complete sentences and context inside each post while keeping independent posts separate. Handle quoted snippets, headings and service metadata deliberately.
- Make the text pane readable with consistent paragraph spacing; fit translated overlays without clipping, overlap or visible source text beneath them.
- Compare recognition and translation latency on the same inputs and settings without sacrificing text coverage or translation quality.
- Recheck the supplied source, exported image and interface together, plus additional multi-post and multi-column examples. Check all platforms' relevant image paths before claiming a cross-platform fix.

Earlier paragraph-layout checks remain evidence for their tested inputs; they do not establish quality on this new example. Private screenshots are retained locally outside Git; implementation is not part of the current iOS volume release.
