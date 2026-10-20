[Русский](README.ru.md)

# Isolated Apple Whisper comparison

Research harness only. It does not change Kat's sources, projects, models, preferences or history. The iPhone probe has its own bundle ID, `app.kattranslator.whisper-research`; never install it over Kat or point it at Kat's container.

## Inputs and measurements

Supply a private JSON array containing `id`, `language`, and `path` for each recording. Paths resolve relative to the manifest. Audio must be mono, 16 kHz, little-endian Float32 PCM. Keep recordings, references, transcripts, models, logs and signed builds outside Git.

`Bench.mm` uses the pinned whisper.cpp source with Metal, Flash Attention, four threads, greedy decoding, explicit language, zero temperature, no temperature fallback and no previous context. It measures model loading separately. Pass 0 warms up each recording; passes 1–3 are measured, alternating recording order. JSON includes text, elapsed time, sampled physical footprint and thermal state. This measures ASR only, without capture, translation, speech synthesis or Kat's recording preprocessing.

Run variants sequentially on each device. Reverse variant order in a second block. Do not run concurrent GPU workloads. Treat a different thermal state as a separate block. `phone_run.py --cool` waits up to five minutes for nominal thermal state; failure is recorded rather than silently included.

## Components

- `CMakeLists.txt`: out-of-tree native build; pass `WHISPER_SOURCE` and keep its build folder under an ignored research directory.
- `convert.py`: reads the exact production F16 GGML weights. Produces MLX F16 weights, or the upstream ANE-oriented Core ML encoder with FP16 precision. Core ML conversion requires the pinned whisper.cpp checkout and its Python dependencies. Compile the resulting package with `xcrun coremlc compile`.
- Q8: use the pinned whisper.cpp quantizer with `q8_0`; verify source/output hashes.
- `CoreMLBridge.mm`: experimental replacement for the upstream bridge. `BENCH_COREML_UNITS=off`, `all`, or `cpu-ne` selects native fallback, automatic Core ML placement, or CPU/Neural Engine only. `BENCH_COREML_ENCODER` optionally supplies a shared encoder directory. No vendor source is modified. Requested units do not establish actual per-operation ANE placement.
- `mlx_bench.py`: macOS Python MLX runner with the same PCM, selected language and zero-temperature decoding. Tokenization, timestamp processing and numerical kernels remain implementation-specific.
- `phone_project.py`: generates a disposable native/Swift iPhone project. Supply your own signing team and isolated native/MLX source paths.
- `MLXRunner.swift`: Swift MLX baseline. Its upstream decoder suppresses timestamps; it is not identical to the Python MLX decoder.
- `prepare_swift_fp16.py`: opt-in patch for an isolated mlx-audio-swift checkout. With `BENCH_MLX_FP16=1`, the mel features and synthesized positional encoding retain FP16 instead of promoting encoder computation to Float32. Apply once to the pinned revision; unexpected source text fails explicitly.
- `phone_run.py`: launches only the research bundle, copies only its report, and terminates its process. Supports shared Core ML encoder, compute-unit selection, cooling, and the Swift FP16 experiment.

## Quality and interpretation

Compare transcripts as well as timing, especially names, numbers, dates, omissions and hallucinations. Equality with F16 is agreement, not ground truth. Compute WER only against independently known references; do not label baseline-relative differences as WER. Preserve failed/thermally mismatched runs separately. Model load measurements use a fresh process but may benefit from OS/model compilation caches.

Versions and measured results are recorded in the [dated benchmark report](../../../docs/benchmarks/apple-whisper-acceleration-2026-10-20/README.md). None of these experiments enables a production backend.
