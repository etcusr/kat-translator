# Optional OPUS Big translator

**Current scope (13 October 2026):** the legacy EN↔RU/UK/BE package uses PyTorch Metal FP16 on modern Mac and CTranslate2 CPU INT8 on iOS/Android. The separate catalog now contains 54 OPUS direction packages, including direct pairs without EN, using CT2 CPU on all three platforms. Initial translation selection is Auto; saved manual choices persist. See [current state](CURRENT_STATE.md), [direction integration](android/benchmarks/2026-10-13-opus-directions/README.md) and [Mac legacy-package GPU evidence](benchmarks/mac-opus-gpu-release-2026-10-12/README.md).

## Historical initial EN-package integration

The rest of this document records the original Apple EN-package integration, its old defaults, UI and paths. It does not describe the current Auto planner or the full direction catalog.

OPUS Big is an additional model choice on macOS and iOS. The language-setup download plan recommends OPUS for Russian ↔ English; adding further languages retains the broad-coverage Index/Qwen recommendation. The recommendation is applied only when the user starts that plan. Existing users' selections and the fallback default (Index) are preserved, and the Index native runtime is unchanged. The package supports English ↔ Russian, Ukrainian and Belarusian (six direct directions). It does not silently pivot between the three Slavic languages. Same-language input follows the existing passthrough behavior.

The model information describes the smaller download, lower memory use and offline operation, together with the limits on complex-text quality. The language picker and model information list only the four supported languages.

## Files and runtime

- `App/Resources/opus-package.json` pins all 12 downloads by revision, exact size and SHA-256. The complete package is 492,650,422 bytes. Both directions, both pairs of SentencePiece tokenizers, vocabularies and licenses are required.
- Original weights: Helsinki-NLP `opus-mt-tc-big-en-zle` and `opus-mt-tc-big-zle-en`. Public INT8 conversion: `crash-sv/scribe-translate-ct2`, revision `366ea5f4bd2bc417a7430006408a0c6cd72a9f91`, CC BY 4.0.
- CTranslate2 4.6.0 (`617405f4b050e994e829d527da6caa0e0030afe7`) and SentencePiece 0.2.1 (`31646a467d2051eb904e0b45de3a73e91fe1c1e3`). Native CPU INT8_FLOAT32 with Ruy and Accelerate, four threads and beam size five. This is distinct from the earlier Python/Metal OPUS benchmark.
- `scripts/build-opus-runtime.sh` builds arm64 Mac, iOS and simulator frameworks. It never rebuilds or replaces the Index runtime. `mobile-cancel.patch` adds cancellation checks to greedy/beam decoding and respects the caller's Apple deployment target. Runtime and model license notices ship in `opus-notices.json`.
- `RoutedTranslationBackend` chooses the engine and unloads the previous model when switching. OPUS loads only one direction's weights at a time. Voice, text, camera/image and macOS integration use the same route.
- Input is segmented by source sentences and paragraphs, then split further to fit 480 tokens. End-of-sequence is required; hitting the output limit causes a retry with smaller source fragments. Truncated output is never accepted as a complete translation. No network is used during inference.

## Download and preloading

`OpusPackage` uses existing resumable `ModelDownloader` instances and the verified atomic `PackageStore` installer. Readiness requires the complete package, not just the first model. The models page exposes one aggregate download/pause/cancel/remove row. Background download completion can assemble the full package.

The local device-preload path is `Documents/DevelopmentModels/opus-big/{en-zle,zle-en}`. Files are checked against the same download manifest before being installed in `Application Support/OfflineTranslator/TranslationPackages/opus-mt-big-en-zle-int8`. Only this staging folder is removed after successful verification. Existing Index/ASR/voice files are reused and preserved.

## Validation

The isolated lab at `/Users/USER/Downloads/kat-translation-lab-2026-10-10` contains the frozen 18-text RU↔EN corpus, three native OPUS repeats, six-direction smoke checks, cancellation evidence and quality review (`OPUS-NATIVE.md`). On M3 Pro the two full articles took 10.20 s EN→RU and 4.64 s RU→EN; measured process peak RSS was 486.6 MB. These are standalone Mac measurements, not iPhone performance claims.

Core tests cover all four languages, direct-pair restrictions, default restoration and lossless segmentation. Hosted Mac tests verify routing/unloading; shared `OpusUITests` exercise actual installed weights, six directions, language filtering and model information on both platforms. Device test results are saved under `.build/opus-integration/`.

The separate Index engine comparison finished and its unchanged-project audit passed before this integration began. All 162 Index results were identical, with a median speed ratio of 1.001×. The experimental updated Index runtime is confined to the lab.
