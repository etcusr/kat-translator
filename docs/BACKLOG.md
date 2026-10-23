# Future work

**English** | [Русский](BACKLOG.ru.md)

Deferred tasks, not completed changes or release promises.

## Next release: screenshots, GitHub and App Store Connect

- [ ] Follow the [release presentation and publication plan](publication/next-apple-release-plan.md): refresh screenshots for every OS/interface language, synchronize documentation and descriptions, present galleries in the repository/site, prepare localized release notes and new iOS/macOS versions/builds, then record a short iOS demonstration. This is planned work; no upload or review submission has started.
- [ ] Redesign the GitHub Pages landing page in Kat branding, with the logo, real screenshots and a playable interface/features demonstration; see section 5 of the release plan. Planning only.

## iOS history: collapsible long text

Planned 22 October 2026. **Backlog only; not implemented on iOS yet.**

- [ ] Show a shortened preview of long originals and translations in iPhone/iPad history. Add a clearly labelled tap action to expand the entry in place and collapse it again; short entries should not have an unnecessary expand control.
- [ ] Match the existing macOS history behaviour (`HistoryView.desktopEntry` and `HistoryPreview`) where appropriate. Keep full text in storage and in copy actions; truncation is presentation only.
- [ ] Check both original and translation, independent expansion of entries, long paragraphs/line breaks, Dynamic Type and VoiceOver. Preserve access to audio/image actions and deletion, and prevent scrolling jumps when entries expand or collapse.

## Microphone activity during voice recording

Apple implementation: lime background bars driven by existing PCM/VAD metering; device acceptance is pending. Android remains planned.

- [x] Add a Voice Activity Indicator to the Voice recording interface on iOS and macOS, with Android kept in the cross-platform plan. Show input level and detected speech, with a clear quiet state; do not imply that recognition or translation has finished.
- [x] Animate the indicator in Kat’s visual style: lime accents on a dark surface and smooth responses to voice level, with a reduced-motion alternative.
- [x] Use the existing audio capture/VAD signal without starting a second microphone session. Keep Pause, Stop and Cancel accessible and support compact windows, VoiceOver and reduced motion.
- [ ] Check silence, normal/quiet speech, background noise, pause/resume and background/foreground transitions on devices. The indicator must not affect the recording, saved audio, phrase boundaries or battery/thermal behavior.

## Unified settings and model management

Apple navigation implemented on 22 October 2026: Quick setup and Models and voices share the first Settings group; models, recognition, OCR, voices and downloads have separate destinations. The original wizard stays directly accessible. [Design](design/apple-settings-2026-10-22.md).

- [ ] Apply the same categories and terminology to Android, adapting controls and layout to its native UI.
- [ ] Extend acceptance to iPad, compact desktop windows, large accessibility text and all long localized labels.
- [ ] Check a live or paused network download while navigating the redesigned screens. Download ownership, consent, cancellation scope and model storage are unchanged; navigation checks alone do not prove network-transfer acceptance.

## Mac App Store AI copy after publication

- [ ] After the current macOS 1.0 review and publication, apply the prepared EN/RU/ES/TR AI descriptions, promotional text and keywords from `publication/2026-10-14/macos/` in App Store Connect. Description/keywords may require a new editable version; promotional text can be changed separately where allowed. Do not withdraw or edit the current Mac submission for this metadata task. iOS 1.0.1 and the public project page are updated separately.

## Mac system translation experiment

20 October 2026: [separate test application and measurements](benchmarks/mac-system-translation-2026-10-20/README.md), no production integration.

- [x] Accelerate automatic glossary in Mac lab with morphology and compact context: 6.78→1.97 s preparation, 24.37→20.14 s total; key term fixes retained on one input, remaining nuance differences documented. [Comparison](benchmarks/mac-fast-terms-2026-10-20/README.md).
- [x] Test source-only automatic glossary against current/manual modes on the same Mac image: 3 measured repeats each, 15 tests and real app bridge. Consistency improved, total 24.35 s vs 17.38/18.49 s; preparation included. [Evidence](benchmarks/mac-auto-terms-2026-10-20/README.md).
- [x] Evaluate unchanged fast expanded glossary on eight new synthetic texts/dialogues, seven unquoted: 48 successful requests, reproducible outputs, mixed quality and +3.19 s median paired full latency. [New corpus](benchmarks/mac-glossary-corpus-2026-10-20/README.md).
- [x] Keep the lab glossary optional; then add the tested fast expanded glossary to main Mac Settings as an off-by-default experimental RU→EN Index 9B option. Text/voice requests and complete OCR images have separate document dictionaries. [Local validation](benchmarks/mac-production-glossary-2026-10-20/README.md).
- [ ] Deferred, before broader rollout or enabling by default: reject ambiguous/incorrect glossary targets, reduce low-value preparation and test longer external documents, other directions and live dialogue turns without future context. The synthetic corpus exposed a terminology regression; it is not independent broad quality acceptance.
- [x] Compare Mac neighboring context and a shared document glossary on the same image: 4 modes ×3 measured repeats, separate lab. Hand-prepared glossary is best on this example; automatic extraction was deferred at that checkpoint; see the newer experiment above. Independent-corpus validation remains open. [Results](benchmarks/mac-context-terms-2026-10-20/README.md).
- [x] Fix Mac image progress resetting per OCR block: one scene-wide total, cache-aware monotonic progress, unchanged translation. Core and real OCR/Index regression checks pass. [Evidence](benchmarks/mac-production-residency-2026-10-20/image-progress.md).
- [x] Main Mac: resident translation model, configurable 5-minute default / 1–60-minute idle timer and Index 9B plain chunks, now enabled by default. Local validation only; no upload. [Evidence](benchmarks/mac-production-residency-2026-10-20/README.md).
- [x] Enable Mac Index 9B chunks by default across Text/Voice/Image; keep an ordinary off switch. Remove waiting video players/resources from all app targets. All platform builds and Mac runtime/UI checks pass; installed Mac updated with data preserved. [Evidence](benchmarks/mac-production-residency-2026-10-20/default-chunks.md).
- [x] Mac partial-translation UX: progress and cancellation above the workspace; intermediate text remains visible, without a processing overlay or GIF. Chunking remains optional; translation algorithm unchanged.
- [x] Build a separate Mac app with Apple lowLatency/highFidelity and Kat Index 2B/9B; verify both Kat worker bridges.
- [x] Compare 256 synthetic RU↔EN translations, retain startup/outlier data and manually inspect context, times and pronouns.
- [x] Profile 192 fresh 9B control requests and compare unchanged outputs; maximum 2.41 s. [Investigation](benchmarks/mac-mlx-latency-2026-10-20/README.md).
- [x] Remove repeated model loading in the separate Mac Lab using one resident worker, with a saved idle timer (default 5 minutes, Settings 1–60) and 32 matching regression translations.
- [x] Test 16 new long/context RU↔EN cases ×3: 48 successes, identical outputs, same-case spread ≤4.7%; manual review retains meaning losses. [Report](benchmarks/mac-long-context-2026-10-20/README.md).
- [x] Evaluate experimental whole/plain/context chunk modes in Mac Lab: 108 paired + 12 targeted requests. Experiment withdrawn; active app restored to whole-text translation with resident models and the existing timer. [Historical comparison](benchmarks/mac-chunk-context-2026-10-20/README.md).
- [ ] Further improve document entities and terminology in chunking: local context fixed cross-boundary gender/bank, but Marina became a hotel name. Total speedup is unproven; investigate context reuse without translating overlap repeatedly.
- [ ] Handle long-input/output budgets with context-preserving segmentation; the current 1536-input/2048-total-token limits caused explicit failures in two boundary probes. Preserve separate beds, overnight stays and other constraints in regression checks.
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
