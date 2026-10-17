# Pixel Whisper i8mm comparison — 17 October 2026

The selected improvement keeps the same Whisper large-v3-turbo Q8 file, four threads, greedy decoding, full audio context and flash attention. It changes the CPU matrix implementation to GGML's existing i8mm Q8 block-repacking path. No smaller model, additional weight quantization or audio trimming is introduced.

## Native comparison

All times below exclude model loading. These are standalone runs on Pixel 9 Pro, not end-to-end application latency or repeated calls in one cached context.

| Input | Previous ARMv8.2 CPU | i8mm CPU | Output |
|---|---:|---:|---|
| Private recording, 25.18 s | 13.760 s | 12.510 s | Exact text match |
| Private recording, 28.86 s | 12.380 / 12.376 / 12.560 s | 11.444 / 11.619 s | Exact text match in every run |

The first recording improved by 9.1%. Comparing medians for the second gives 12.380 → 11.532 s, or 6.9% less inference time. Model loading was approximately 0.92 s before and 0.70 s with i8mm. Numbers, dates, times and complete sentence order matched the baseline. These are small repeated samples, not a statistical or multilingual accuracy guarantee.

[Machine-readable measurements](measurements.json) include all screening runs, short Russian/English controls, thermal observations, profile results and application acceptance. Private recordings and transcripts are excluded.

## Rejected alternatives

| Same Q8 input, 28.86 s | Inference | Decision |
|---|---:|---|
| Vulkan / Mali, flash attention on | 67.334 s | Much slower than CPU |
| CPU, flash attention off | 13.659 s | Slower than the current default |
| Arm KleidiAI 1.24.0, two runs | 9.515 / 9.504 s | Not selected: additional weight requantization and different text |

KleidiAI was the largest inference gain, but loading increased to about 3.28 s. Its Q8 path converts block-scaled Q8 weights into channel-scaled int8; it is not just a layout change. Both private recordings retained their numeric details, but one gained a preposition and the other changed a word's spelling. This does not prove general degradation, but it fails the conservative exact-text acceptance criterion. It remains an isolated experiment; production explicitly disables KleidiAI. Vulkan and reduced flash-attention settings are also absent from the application change.

The chosen i8mm build uses `armv8.2-a+dotprod+fp16+i8mm`, rather than raising the entire architecture requirement to ARMv8.6. Existing Q8 blocks are repacked as `q8_0_4x8`; there is no conversion to KleidiAI weights. The pinned shared vendor source is unchanged.

## Profile and remaining work

A separate `simpleperf` run sampled only the probe's user-space process at 1 kHz: 49,903 samples. Self CPU samples attributed 33.20% to Q8 matrix multiplication, 29.56% to flash attention, another 2.11% to its single-chunk helper, and 4.48% to softmax. The graph worker accounted for 11.31%; inlining and thread synchronization limit finer attribution. These percentages are CPU samples across threads, not fractions of wall-clock time. The profiler's inference time is excluded from the speed comparison.

The encoder still dominates (about 9.6 s with i8mm versus 10.5–10.6 s before). Larger gains require measured improvements to matrix/attention kernels or a same-checkpoint runtime experiment. CTranslate2/Ruy is a possible follow-up, with model conversion and a mel frontend required; it was not integrated or benchmarked here. LiteRT-LM translation benchmarks are not evidence of faster Whisper recognition.

## Integration and checks

The application includes a separate optional `kat_whisper_i8mm` library. A baseline-code HWCAP/HWCAP2 check requires FP16, dotprod and i8mm before loading it. Only the verified Q8 model filename selects this path. F16 and other model filenames keep the previous ARMv8.2/baseline selection; missing optional libraries fall back without changing the user's selected model.

Every backend has distinct JNI entry points. `WhisperModelCache` records the library owning each handle and releases through that owner before a model/backend change. Cache hits, failed creation, retry and idempotent close are covered by nine new JVM tests. Existing model retention, memory-pressure release and cancellation policies remain in effect. Diagnostic recognition measurements now record the actual backend.

Native setup and the complete application/test builds passed, together with **127 JVM tests** and Android lint. The new library exposes only its four distinct JNI functions and has 16 KB load-segment alignment; this is not a fresh physical 16 KB-page device test. The reusable native probe accepts `build.sh i8mm` after `setup-media.sh`.

Fresh ordinary audio-import tests compared the previously installed application with the new development build:

| Recording | Previous recognition | i8mm recognition | Change |
|---|---:|---:|---:|
| 25.18 s | 14.027 s | 12.974 s | −7.5% |
| 28.86 s | 13.717 s | 12.543 s | −8.6% |

Both application transcripts match their respective previous-build transcripts byte for byte. The new test records and asserts `runtime: i8mm`, so silent fallback cannot masquerade as acceptance. No sampled CPU/GPU/uclamp restrictions or non-NONE Android thermal status occurred in these four app measurements. Automatic speech was disabled to isolate recognition; these are not first-sound timings. One app pair per recording is not a repeatability distribution.

Development **0.4.6 (21)** is installed on Pixel. Saved distribution APKs and Apple builds were not replaced. Fresh device checks passed: ten native boundary cases, two new-build audio imports, cancellation followed by cache reuse and memory-pressure release, and real Q8 → F16 → Q8 model creation/free across libraries. The last test cancels after each model load to isolate ownership; it does not claim new F16 inference acceptance. Its first attempt used the upstream F16 basename instead of the installed catalog filename and failed before loading that model; the test path was corrected and the isolated rerun passed.

Installed APK SHA-256: `8bbb6138085d488e0b2ededb2e28aed4075d6f8a0c5d89a7d4e5a3e47e8cdd68`. It matches the built APK. All 35 saved preference values matched the pre-test snapshot; temporary task files were removed and the normal app reopened. Screen brightness was not changed, and the existing stay-awake setting was preserved. No GitHub push, store upload or distribution refresh.

Rebuild with `scripts/android/setup-media.sh`; `scripts/android/whisper-probe/build.sh arm82` and `build.sh i8mm` produce comparable probes. Run both with the same Q8 file, 16 kHz WAV, four threads and explicit language. For the app, `RecognitionLatencyTest` accepts `recognitionLatency=true`, `recognitionModel=whisper-large-v3-turbo-q8_0` and `recognitionRuntime=i8mm`. `WhisperBackendSwitchTest` requires `whisperBackendSwitch=true` and both existing Q8/F16 packages. Tests restore saved preferences; private input/transcript files must remain outside Git.

## Measurement boundaries

Each native run starts only after two fresh HAL readings ten seconds apart meet skin ≤34.5°C, battery ≤35.5°C, G3D ≤45°C, Android thermal status NONE and no CPU/GPU/uclamp restriction. There is no fixed cooldown duration. Restrictions or skin ≥38°C/battery ≥39°C abort the owned probe; G3D warnings are retained in the results. Charging restrictions are distinguished from compute restrictions. Screen brightness and the user's stay-awake setting are preserved.

This checks imported recordings and pre-existing short test audio, not live microphone capture, noisy multilingual speech or a human listening/scoring panel. English control audio was resampled once from 22.05 kHz to 16 kHz for both implementations. Equal output establishes no observed regression on these inputs, not universal recognition equivalence.
