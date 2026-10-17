# Pixel Whisper variants — 17 October 2026

Follow-up to the [CPU instruction fix](../2026-10-17-whisper-latency/README.md). Same private 25.179875-second mono/16 kHz recording, explicit Russian, pinned whisper.cpp v1.9.4, no prompt or transcript hints. Results below separate standalone inference from the application pipeline.

## Native screening

| Variant | Inference | Text quality relative to full Turbo F16 |
|---|---:|---|
| Turbo F16, 4 threads | 23.69 s | Reference |
| Turbo F16, 6 threads | 27.48 s | Exact match; slower |
| Turbo Q5, 4 threads | 31.45 s | Same key details; one added preposition; slower |
| Turbo Q5, i8mm | 33.58 s | Same Q5 result; slower |
| **Turbo Q8, existing ARMv8.2 runtime** | **13.48 s** | **Exact match** |
| Turbo Q8, experimental i8mm runtime | 12.74 s | Exact match |
| Whisper Base | 2.44 s | Missing numbers and corrupted opening |
| Whisper Small | 7.23 s | Numbers/names retained, greeting replaced |
| Whisper Small, beam search 5 | 22.94 s | Opening still wrong; slower |
| Turbo F16, audio context 1280 | 46.79 s | Corrupted opening and invented trailing text |

All rows use four threads, greedy decoding and default audio context/flash attention unless specified. Model-load times and initial/final thermal observations are in [measurements.json](measurements.json). Each screening run began with no CPU/GPU/uclamp restrictions and thermal status NONE; some heated into throttling. These are exploratory single runs, not repeated thermally identical rankings. A transcript match is relative to full F16 on this input, not a human-scored multilingual accuracy claim.

Q8 was selected. It retains the large-v3-turbo architecture with 8-bit weights and uses GGML's existing optimized CPU repacking/matrix path. Q5's smaller file did not make its kernels faster here. The extra i8mm library improved the single Q8 observation by only about 6%; that does not justify another hardware-specific production library on these measurements. No i8mm, beam-search or reduced-context change is shipped.

## Application comparison

The normal app import pipeline on the same recording, automatic speech/history saving disabled:

| Package | Recognition | OPUS translation | Total before speech |
|---|---:|---:|---:|
| Turbo F16 | 26.03 s | 3.40 s | 30.15 s |
| **Turbo Q8** | **14.36 s** | **3.34 s** | **18.35 s** |

Recognition is **1.81× faster (44.8% less waiting)**. The spoken words, numbers and time are identical; F16 adds a pair of quotation marks around the second utterance, which Q8 omits. Thus the app transcripts are not byte-identical, unlike the native screening pair. No vocabulary, digit sequence or date/time regression was observed on this recording.

Both app runs began at thermal status NONE, skin below 35.5°C, battery below 37°C, and without CPU/GPU/uclamp restrictions, confirmed twice ten seconds apart. Neither ended with compute restrictions. Starting skin temperatures were 34.31/34.95°C; ending temperatures 36.04/36.64°C for F16/Q8. Charging restrictions differed and are not CPU throttling. These are one run per package, not a repeated statistical benchmark. The previous **37.67 s** F16 observation was a different, warmer run; the fresh **26.03 s** is the appropriate baseline here.

## Integration and checks

- Added the optional Q8 catalog package and Whisper language aliases; its routing regression failed before integration, then passed. Auto routes and saved user choices are unchanged by an app update.
- Built an isolated source snapshot of `f0a4ae7` plus this task's Android catalog, loader and test changes. Concurrent Apple/voice-default work was excluded from the installed APK. App/test APK builds, **108 unit tests (68 app + 40 inference)** and Android lint passed. The native comparison probe also built successfully.
- **Five device tests passed:** two app latency runs, Q8 cancellation/reuse, and two voice-result/playback tests. Q8 cancellation reached idle in **214 ms**, produced no partial result and allowed the next OPUS translation.
- An initial Q8 app run stopped before inference because a manually staged package was not recognized. Removed only that newly staged directory, then installed Q8 through the actual Models download button; the app displayed **downloaded and verified**. The reported successful comparison uses this normal installation.
- All 34 saved preference fingerprints, including history, matched after tests. Q8 was then explicitly selected through Models; only `recognitionPreference` and `recognitionModel` changed. The full F16 package remains installed. Temporary device benchmark audio/results/probes were removed after validation.
- Installed development APK remains **0.4.6 / code 21**. Saved distribution APKs and Apple installations were not replaced. Bilingual docs parity checks passed.

Quality evidence is limited to this imported Russian recording. No live microphone, noisy/multilingual corpus, listening panel, older CPU or 16 KB page-size device rerun is claimed. Q8 quantization is not numerically lossless and may produce different recognition on other inputs; the measured case retains all spoken words.

## Model provenance

- Q8: `ggml-large-v3-turbo-q8_0.bin`, 874,188,075 bytes; SHA-256 `317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1`.
- [Pinned upstream Q8](https://huggingface.co/ggerganov/whisper.cpp/blob/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q8_0.bin): revision `5359861c739e955e79d9a303bcbc70fb988958b1`. A fresh HTTP check returned the same linked size/hash and a successful download target. Local conversion from the verified F16 model using the pinned quantizer reproduced those exact official bytes.
- Q5: existing official package, 574,041,195 bytes, SHA-256 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.
- [Small upstream file](https://huggingface.co/ggerganov/whisper.cpp/blob/main/ggml-small.bin): downloaded at the same pinned revision; SHA-256 `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` verified. Base provenance is in the existing [research inventory](../../research/whisper-small-candidates.json).

Q8 is an explicit Android recognition package with the same language mapping as F16. Auto still routes Russian to GigaAM and other supported languages to Parakeet; F16 remains available. No smaller-model substitution or silent selection migration is introduced. The optional ARMv8.2 CPU library and legacy fallback from the previous change are reused.

## Reproduction

`scripts/android/whisper-probe/build.sh arm82` builds the existing CPU probe. Its optional arguments after `MODEL WAV THREADS LANGUAGE` are flash attention (0/1), audio context (0 means default), and beam width (1 means greedy). The i8mm experiment was separately linked against the same pinned vendor source with `GGML_CPU_ARM_ARCH=armv8.6-a+dotprod+fp16+i8mm`; it was only run after confirming hardware support. It is not part of APK setup.

`RecognitionLatencyTest` accepts `-e recognitionLatency true` and `-e recognitionModel whisper-large-v3-turbo-q8_0` (F16 remains its default). `SpeechCancellationTest` accepts the same model selector. Input is `cache/asr-latency-input.wav`; timing JSON and transcript remain in private app cache. Tests disable history/audio saving and restore preferences. No recording or personal transcript belongs in Git. This is audio import validation, not live microphone acceptance.
