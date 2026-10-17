# iPhone voice latency — 17 October 2026

Follow-up: [streamed speech correctness fixes](../apple-speech-correctness-2026-10-17/README.md) retain complete sentences, avoid whitespace-triggered replay, correct contextual ordinals and enable default Mac MLX partial output. The latency measurements below predate those fixes and are not a fresh timing result for the corrected implementation.

Request: speed up recognition, translation and speech on iOS without lowering quality.

## Method

iPhone 17 Pro, development builds of 1.0 (51/52), built-in `RecordingPreviewProbe` (fixed synthetic recordings replayed instead of the microphone; Whisper large-v3-turbo F16, Index 9B with MTP, Piper). Each run: unmeasured warmup, then "after stop" (processing starts when recording ends — the default until now) and "during recording". Times are seconds from the end of recording.

## Baseline

| Phrase | Recognition | Translation (first token) | Speech starts |
|---|---|---|---|
| Short RU→EN, 2 sentences | 1.1–1.4 | 1.3–2.3 (0.6–1.6) | 3.6–5.1 |
| Medium EN→RU, 20 s of speech, 5 sentences | 1.4 | 5.3–5.4 (0.7) | 7.1–7.2 |

Translation was 70–75% of the wait, and speech waited for the whole translation. Recognition and Piper were already fast.

## Changes

1. **Speech during translation.** The translation runtime exposes the text generated so far (`ot_mt_partial`; normal and MTP paths). The pipeline speaks each finished sentence while the rest is generated (next sentence synthesized during playback). The translation is a single unchanged pass; only the start of speech moves.
2. **Piper uses up to four threads** on iPhone/Mac, as on Android.
3. **Processing during recording is on by default** (owner decision); an explicit user choice is kept.
4. Checked, not changed: re-enabling persistent Metal residency (disabled on 17 Oct for the microphone fix) gave no warm speed gain and made processing during recording slower with one failed run.

## Result (medium phrase, after stop)

| Build | Translation | Speech starts | Longest pause between parts | Total |
|---|---|---|---|---|
| Before | 5.28–5.43 | 7.06–7.23 | — | 23.3–23.5 |
| After | 5.74 | **3.14** | 0.25 | 20.5 |

Translated text identical. During recording: speech starts after 0.1–0.3 s in both builds. The short phrase gains little because its translation ends almost together with its first sentence (3.6 → 3.7 s, within run-to-run variation). The "after" run used the Irina voice (new default), the baseline Denis.

## Limits

One device; the phone throttled after repeated runs and several runs were skipped by the probe's thermal guard. No listening panel. Single measured run per build; numbers are observations, not a guarantee. Real microphone capture was not part of this probe.

Follow-up: the [translation settings comparison](../ios-mt-options-2026-10-17/README.md) retained MTP with two draft tokens. It did not change model weights or provide a new speech-latency baseline.
