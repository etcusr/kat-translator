# Isolated Index quantization comparison

**English** | [Русский](README.ru.md)

This research harness reads explicitly supplied GGUF models and the native TranslationRuntime library. It does not launch Kat, read its history/preferences, replace models, or change application defaults. Corpus: 30 fixed Russian/English cases with provenance; see [protocol](../../../docs/benchmarks/index-quantization-2026-10-21/PROTOCOL.md).

Compile `Memory.mm` as a dylib with Foundation and Metal. Run `run.py --help` for paths. Use a fresh output path: existing measurements are never overwritten. Set `GGML_METAL_NO_RESIDENCY=1` consistently. Run each model sequentially with identical library/metrics/corpus, two measured passes after two warmups; avoid concurrent downloads or compilation. Verify model SHA-256 against the pinned official metadata before use.

`python3 scripts/research/index-quantization/summarize.py PRIVATE_RESULTS_FOLDER` validates all four runs and writes summaries plus anonymized translations and a separate label key. Review source meaning before opening the key. The summary does not calculate an automatic translation-quality score.

Memory fields are separate: `footprint` is charged physical footprint; `resident` is resident size including mappings; `resident_process_peak` is lifetime high-water mark; `metal_allocated` is the Metal allocation counter and is not an independently additive RAM measurement. Samples every 100 ms can miss brief peaks. Timings exclude download/hash verification and report model load separately. System swap/thermal context is recorded. These are GGUF engine measurements on Mac, not Mac MLX/MTP2 or iPhone application acceptance.
