# Android Whisper latency — 17 October 2026

Whisper large-v3-turbo F16 was slow primarily in its encoder, rather than model loading. The Android build targeted baseline arm64 and did not enable the Pixel CPU's FP16 vector/dot-product instructions. The production fix packages a second CPU library and selects it only after a baseline hardware capability check. Model weights, decoding parameters, four inference threads and cancellation behavior are retained.

## Native diagnosis

One local 25.179875-second, mono 16 kHz recording; Pixel 9 Pro; the same installed, verified `whisper-large-v3-turbo-f16` package. Greedy decoding, explicit Russian, no context, temperature zero, no fallback temperatures. The original and optimized CPU variants and the Vulkan candidate returned exactly the same transcript, including the technical names, number sequence and date/time. This is a single-recording comparison, not a general language-quality benchmark.

| Variant | Model load | Inference | Encoder | Decoder |
|---|---:|---:|---:|---:|
| Original baseline CPU | 2.333 s | 117.417 s | 105.471 s | 11.567 s |
| CPU FP16/dotprod | 1.112 s | 28.093 s | 23.379 s | 4.463 s |
| Vulkan experiment | 1.191 s | 67.567 s | 62.730 s | 3.419 s |

CPU inference improved 4.18× in this diagnostic comparison. GPU was slower than optimized CPU and was not integrated. Native runs were exploratory rather than a thermally matched repeated benchmark. The app comparison below separately records temperature/frequency restrictions and includes the product pipeline.

Parakeet TDT v3 INT8 took 2.491 s to load and 2.059 s to recognize the same recording, but omitted the greeting and still mangled the technical names. It did not establish a quality improvement over the current Russian GigaAM choice. Replacing the recognizer with a smaller/quantized Whisper was not necessary for the measured CPU gain.

## Product comparison and checks

Same input through the normal import → Whisper → OPUS path, automatic speech/history recording disabled only during the test:

| Product stage | Baseline CPU | Optimized CPU |
|---|---:|---:|
| Recognition | 117.414 s | 37.672 s |
| Translation | 3.495 s | 4.319 s |
| Total processing | 121.664 s | 42.731 s |

Recognition was **3.12× faster (67.9% less waiting)**. The two app transcripts were byte-for-byte equal. Both runs began with thermal status NONE and no CPU/GPU/uclamp frequency restrictions. Both heated into throttling: baseline ended at CPU cooling 8/3; optimized ended at 10/6, uclamp restrictions and thermal status LIGHT. Starting temperatures also differed; exact snapshots are in the JSON. This is one observed before/after app comparison, not a sustained-speed or thermally identical benchmark. The optimized app result is therefore reported as 37.67 s, separately from the 28.09 s standalone inference result.

The baseline app was the same new APK with only the optional optimized library omitted, re-aligned and signed with the same development key. This exercises the actual library-load fallback without adding a production test switch. The complete optimized APK was restored afterward. No uninstall, version change or distribution artifact replacement was performed (development 0.4.6/code21).

Validation:

- Native setup, both probe builds, app/test APKs, 107 unit tests and Android lint passed.
- Both product latency runs passed. Initial input transfer failed the test's file requirement before inference; copying the file correctly resolved the harness error.
- Seven physical native boundary tests passed, including optimized-library packaging/loading, pre-cancelled requests and corrupt models; baseline entry points remain covered.
- Active Whisper cancellation returned to idle in 433 ms with no partial text, then OPUS translation succeeded (one test).
- Both voice-panel/playback regression tests passed. Together with latency and boundary checks: 12 successful device tests.
- Saved preferences/history fingerprints were identical before and after all tests. Afterward, Whisper was selected through Settings on the acceptance Pixel. Only `recognitionPreference` changed; every other preference/history fingerprint stayed identical. Temporary device input, transcript, results and native probes were removed.
- Exported ELF symbols are limited to each library's distinct JNI method; load segments are aligned to 0x4000. `kat_media` has no dependency on the optional library. Physical old-CPU and 16 KB-page device validation remain unavailable.

The model, weights/precision and decoding policy are unchanged. FP16 vector kernels can differ numerically from baseline kernels; exact transcript equivalence here is evidence for this recording, not a guarantee for every input. No live-microphone, noisy/multilingual corpus, new GPU-runtime or release acceptance is claimed.

## Integration and compatibility

- `scripts/android/setup-media.sh` builds baseline `libkat_whisper.so` with `armv8-a`, and `libkat_whisper_arm82.so` with `armv8.2-a+dotprod+fp16` in separate build trees.
- `kat_media` checks `HWCAP_ASIMDDP`, `HWCAP_ASIMDHP` and `HWCAP_FPHP` before the optional library can load. Unsupported hardware and `UnsatisfiedLinkError` retain baseline Whisper. No change to the minimum Android API or arm64 requirement.
- Gradle packages the optional library without a `DT_NEEDED` dependency. Its exported JNI entry point has a distinct name; GGML/Whisper symbols remain hidden. This also isolates Whisper from Index's incompatible GGML ABI.
- Both libraries retain 16 KB ELF segment alignment and the existing Android cancellation patch. The optimized stripped library adds 1,383,400 bytes (about 1.4 MB) before APK compression/alignment.
- Auto still routes Russian to GigaAM and other supported languages to Parakeet. Explicit Whisper selection uses the accelerated path where supported. Apple runtimes are unchanged.

## Reproduction and privacy

Run `scripts/android/setup-media.sh`, then build the app and instrumented tests. `RecognitionLatencyTest` is opt-in (`-e recognitionLatency true`) and imports `cache/asr-latency-input.wav`; it disables recording/history and automatic speech for the test, restores settings, and exports timing JSON and a private transcript only to app cache. Its instrumentation logs contain no transcript. The recognition timer includes the ordinary audio-to-recognizer product path; translation is measured separately. This is an imported-audio test, not live microphone acceptance.

For isolated CPU profiling, build `scripts/android/whisper-probe/build.sh baseline` and `scripts/android/whisper-probe/build.sh arm82`. Copy the probe and its Sherpa/ONNX dependencies to a temporary device directory and run `whisper-<variant> MODEL WAV 4 ru`. The arm82 probe is for a separately confirmed compatible CPU; hardware selection is provided by the app, not by this standalone executable. Native diagnostics print the transcript locally: do not commit their raw output or personal audio.

[Measurements](measurements.json) contain only anonymous timings and equality results. Source audio, text, device identifiers, APKs and raw logs remain outside Git.
