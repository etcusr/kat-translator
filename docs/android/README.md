# Android: architecture and porting history of Kat translator

**English** | [Русский](README.ru.md)

Current release: **0.4.6 / code 21**. Compose, text/voice/camera, history and downloads; Index 9B on Vulkan with MTP, Index 2B on Vulkan without MTP, OPUS on CPU with separate directions, GigaAM/Parakeet ASR Auto. The initial translation choice is "Auto", based on the device class and language pair; a saved manual choice is kept. The initial CPU/GPU device check runs before language selection. [Current state](../CURRENT_STATE.md) · [install and build](INSTALL.md) · [actual layout](PLATFORM_LAYOUT.md).

Latest [RU/DE voice acceptance](../benchmarks/voice-auto-devices-2026-10-13/README.md): import and the physical Pixel microphone, GigaAM/Parakeet → Auto OPUS/Index 2B → TTS. The Voice source language is chosen explicitly; ASR Auto selects an engine, it does not detect an unknown spoken language.

## Porting history and initial decisions

The assessment and porting stages before the current release are kept below, including earlier plans, defaults and results of individual builds. They are not the current specification or a list of missing features. The old description of the uncommitted tree refers to the period before the history cleanup; continue from `main` following the [Git workflow](../GIT_WORKFLOW.md).

Historical Android 0.2.1 measurements: profiling localized the latency in GPU matrix kernels. Choosing a different
generation kernel on the Mali-G715 reduced a repeated short phrase from 8.51 to 7.29 s
without changing the model. [Measurements, failed experiments and reproduction](benchmarks/2026-10-12-pixel9pro-index-profile/README.md).

Android 0.2.2: [prefill optimization, MTP profile and approach search](benchmarks/2026-10-12-pixel9pro-mali-research/README.md).
For an 82-token input, prefill went from 8.68 to 6.68 s in the diagnostic runtime, without changing
Index/Q4_K_M. A short translation in the APK stayed at 7.23–7.27 s. MTP showed a
preliminary gain in separate diagnostics; it has been integrated since version 0.3.1.
Controlled speed measurements accounted for heating; later functional
checks run without pauses. Controller history is
[here](benchmarks/2026-10-12-pixel9pro-thermal-mtp/README.md).

[Current state](../CURRENT_STATE.md) · [Pinned inputs](portability-contract.json) · [Checks](../../scripts/validation/test_android_readiness.py)

## Conclusion

The port is realistic. The proposal is **Kotlin + Jetpack Compose for Android, C/C++ via JNI for inference**, with shared model files, catalog and reference fixtures. The original baseline was ARM64 CPU; after comparing and fixing the Mali computations, the main Android mode is Vulkan GPU. Having a Tensor G4 does not mean an arbitrary GGUF model can use its TPU.

Upstream Android support of a library confirms the porting path but not the speed, stability or compatibility of a specific Kat version. **Index, OPUS, Whisper, Piper, Supertonic, Wayu, OCR, camera and the full import → recognition → Index → speech → export flow were verified on the Pixel. OmniVoice was fixed and passed real synthesis; all 8 checks of the fixed menu and settings passed. Whisper and OmniVoice recognition/synthesis are still slow.** Further functional tests run without thermal pauses, separately from comparable performance measurements. Local JDK 17, SDK/NDK and ADB are installed in `.build/android-tools`. Pixel: Android 17 / API 37, 4 KB pages, about 16 GB RAM. Apple builds were verified after the migration at the previous stage. Original measurements: [description of the kept material](benchmarks/2026-10-11-pixel9pro-index-cpu/README.md).

Project sources: the current sections of `docs/CURRENT_STATE.md`, `README.md`, the two Xcode project generators, `shared/native/`, `shared/packages/` and `assets/catalogs/`. Historical models from old reports are not part of the main Android set. At the time, the working tree had many uncommitted changes; the reorganization was done on top of the current tree, keeping the original snapshot and without discarding changes.

## Architecture and alternatives

| Option | What is reused | Cost and decision |
|---|---|---|
| **Kotlin/Compose + shared C/C++** | Weights, tokenizers, C ABI, catalog, reference data | Recommended: predictable integration of camera, audio and lifecycle; Swift policy is ported together with parity tests |
| Kotlin UI + a separate Swift core | Part of the pure Swift business logic | A real option: an official Swift SDK for Android exists. But the current `OfflineCore` contains AVFoundation, Combine, NaturalLanguage, Darwin, ImageIO; a portable package would have to be split out and another toolchain added |
| Flutter + C/C++ | Weights and inference | Needs a new UI and platform bridges; gives no automatic SwiftUI reuse for the first Android port |

SwiftUI, Vision, Metal, Core ML and AVFoundation do not come along with the Swift SDK. The Kotlin proposal therefore follows from the composition of the current project, not from a claim that Swift does not work on Android. [Swift SDK](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html).

## Unified repository structure

Target structure after a separate, verified migration:

```text
apps/
  ios/                         # iOS entry point, camera, widget, plist, Xcode project, UI tests
  macos/                       # Mac entry point, hotkeys, menu bar, plist, Xcode project, UI tests
  android/                     # Gradle, Compose, Android services, JNI, instrumentation
shared/
  apple/                       # shared iOS/macOS SwiftUI screens and Apple adapters
  packages/                    # OfflineCore and SpeechRecognitionRuntime; Apple packages for now
  native/                      # TranslationRuntime, Whisper glue, TTS, OCR, fastText
  contracts/                   # catalog formats, history, golden fixtures
assets/
  catalogs/                    # single source of model and voice metadata
  bundled/                     # small shared resources: lid.176.ftz, dictionaries, graphics
  licenses/                    # model cards, notices, licenses
model-store/                   # ignored by Git; one local weight cache per computer
  blobs/sha256/                # each portable file stored once by digest
  packages/                    # package composition: links to blobs, not copies of weights
dependencies/
  locks/                       # commit, patch digest, SHA-256 and build options
  vendor/                      # engine sources; shared cache, outside Git
scripts/
  ios/
  macos/
  android/
  validation/
tests/fixtures/                # shared text, audio and OCR samples
docs/                          # instructions and reports
.build/<platform>/<abi>/       # platform build outputs, outside Git
dist/<platform>/               # signed installers, outside Git
```

**The platform migration is done; the actual paths are listed in the [directory map](PLATFORM_LAYOUT.md).** The original porting plan is kept below. Portable models stay in the shared store, without per-platform copies.

Porting maps:

- `App/` could not simply become `apps/ios`: `scripts/generate-macos-project.py` includes most of its files. The shared Conversation, History, Models, Settings screens and Apple adapters move to `shared/apple/`; the iOS entry point, UIKit camera and Live Activity move to `apps/ios/`.
- `MacApp/` → `apps/macos/`; `DownloadActivity/` and `Shared/DownloadActivityAttributes.swift` → `apps/ios/`; `Shared/CatProgressDrawing.swift` → `shared/apple/`.
- `Packages/` → `shared/packages/`; the C/C++ parts of fastText/archive move to `shared/native/` with adjusted SPM references. `Native/` and the C glue from `App/ASR`, `App/Speech`, OCR → `shared/native/`, with separate platform adapters.
- `App/Resources/*-package*.json`, `voice-manifests.json`, `additional-voices.json` and model parameters from Swift → `assets/catalogs/`. The catalog API is split per platform with a capability filter, not by copying JSON.
- Portable graphics, OCR dictionaries, fastText and voice previews → `assets/bundled/`. Asset catalogs and per-platform InfoPlist icons/localizations stay with their platform or are generated from a shared source.
- Xcode projects, schemes, relative SPM paths, bridging headers, packaging scripts, build identity and test fixture paths are updated in one migration. Case-sensitive Linux CI is checked separately: `Shared` → `shared` and `Dependencies` → `dependencies` on macOS go through an intermediate name.

### Models and voices without duplication

One catalog describes `{id, revision, engine, format, artifacts, languages, license, platformStatus}`. Each artifact has `sha256`, `byteCount`, a URL and a safe relative path. A file's identity is its digest, not an app name or extension. Portable GGUF/GGML/ONNX/SPM/dictionaries are not spread across the three `apps/`.

`model-store/blobs/sha256/<digest>` is one immutable blob on the developer's computer. A package is a manifest referencing blobs. Since several engines expect neighbouring files with specific names, the resolver may create read-only hardlinks in `model-store/packages/<id>/<revision>/` on the same file system; if hardlinks are impossible, it resolves paths directly or stages explicitly, without hidden permanent copies in every app. A blob is checked for changes before reuse.

This store is meant for development and testing. **On different physical devices the models are necessarily downloaded separately**, into the app's private storage. Engine binaries also differ: Mach-O/XCFramework for Apple and ELF `.so` for Android are not interchangeable. Small resources may ship in every installer but have one source in the repository. The 5.78 GB Index download is not part of the APK; importing from a file copies/moves it into private storage instead of relying on direct `mmap` of an arbitrary Android `content://` URI.

Core ML `.mlmodelc` is marked `apple-only`; a shared ONNX file is marked as a portable candidate, but `android=verified` is set only after a smoke test of that exact digest. Successfully parsing the catalog does not raise this status.

## Libraries: what ports and what is replaced

| Component and project version | Android path | Status / required work |
|---|---|---|
| llama.cpp `d81235049384534c167caea52b85a694f6103d14` (`v0.6.0`) | NDK/CMake, CPU ARM64, then Vulkan | Upstream has an Android binding. Build exactly the pinned commit. Our `TranslationRuntime.cpp` sets `n_gpu_layers=99` and forced Flash Attention: move backend, offload and FA into configuration; CPU baseline uses offload=0 |
| whisper.cpp `927cfce34f31707e17f2bff35c349632fb9e2c3a` (`v1.9.4`) | NDK; same GGML file | There is an official Android example. Do not blindly carry over Apple `use_gpu=true`; CPU baseline and a separate Vulkan assessment |
| sherpa-onnx `v1.13.8`, commit `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf` | Android JNI/C API | Android apps exist, including Supertonic. Needs an Android artifact instead of the XCFramework, operator checks, data files and 16 KB ELF |
| ONNX Runtime: iOS lock `1.28.1`, Mac script uses `1.30.0` | One consistent Android ORT CPU build | These are already different versions in the project. Align the version with sherpa, pin commit and SHA of the Android AAR/so; check Wayu/OCR/ASR. Do not package two conflicting `libonnxruntime.so` |
| Piper/VITS, eSpeak NG, phonemization | sherpa C API and its dependencies, data directory | ONNX ports; do not forget dictionaries, espeak-ng-data and notices. The runtime license does not replace each voice's license |
| Silero VAD `643854` bytes | sherpa/ORT on CPU | Portable ONNX model; keep the 16 kHz input and state/reset between recordings |
| fastText `v0.9.2`, `lid.176.ftz` | C++17 + JNI | The sources are already in the project. Apple NaturalLanguage participates for ambiguous/short phrases; an Android fallback needs new rules and tests, without silently claiming equivalence |
| CTranslate2 `v4.6.0`, commit `617405f4b050e994e829d527da6caa0e0030afe7` | NDK + RUY, `WITH_ACCELERATE=OFF` | Second priority after Index. The current CMake is Apple-only. RUY in this commit contains INT8 and FLOAT GEMM; check the real attention GEMM/leading dimensions. Keep `mobile-cancel.patch` |
| SentencePiece `v0.2.1`, commit `31646a467d2051eb904e0b45de3a73e91fe1c1e3` | C++17 static, no training/CLI | Needed for OPUS, not for GGUF Index whose tokenizer is inside the file |
| OmniVoice `53e6c2066150802ad3cd4b655b31c696e78e0019` | Separate NDK runtime | Has a local cancellation patch. Currently OBJC, Metal, Accelerate and an Apple export list in CMake; a full port was not yet proven |
| Wayu ONNX + Python G2P | ORT + an Android Python frontend or a native G2P port | ONNX alone does not solve Thai phonemization. `WayuFrontend.c` contains `mach-o/dyld.h` and Apple paths. First a Chaquopy probe with pinned tltk/pythainlp/dictionaries; no network resource downloads during speech |
| FluidAudio / Parakeet Ultra Core ML | Exclude this package from the Android catalog | Needs a different ONNX export and new measurements if the feature is needed; do not promise a conversion |
| Apple Speech, Core ML, Metal, Accelerate | Whisper/sherpa, CPU/Vulkan, RUY | Apple APIs do not exist on Android; do not use system cloud ASR/TTS as a hidden fallback |
| Vision / current HybridOCR | CameraX + a full ORT detector/recognizer OCR | The repository only has RU/EN recognizers; the detector is currently Vision. Add and pin an ONNX detector, preprocessing, NMS/boxes, orientation and CTC decode |
| AVFoundation, UIKit, AppKit, ImageIO | AudioRecord/AudioTrack, MediaCodec/MediaExtractor, CameraX, Android image APIs | The platform layer is rewritten: pause, stop, audio focus, routing, rotation, capture/import/export |
| Combine/SwiftUI/Observation | Compose + ViewModel + StateFlow/coroutines | Keep the pipeline states and cancellation; do not port UI files mechanically |
| CryptoKit, URLSession, archive C/bz2 | MessageDigest SHA-256, HTTP download adapter, tar/bzip2 library | Range/ETag, atomic rename, protection against traversal/symlinks, disk full; do not assume a system bz2 in the NDK |
| History, preferences, Share sheet | Room/DataStore, FileProvider, Android Sharesheet | Import/export of the shared schema, retention rules and exclusion of private data/weights from backup |

Upstream: [llama Android](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md), [Whisper Android](https://github.com/ggml-org/whisper.cpp/blob/master/examples/whisper.android/README.md), [sherpa Android](https://k2-fsa.github.io/sherpa/onnx/android/index.html), [Supertonic Android](https://k2-fsa.github.io/sherpa/onnx/tts/all/English/supertonic-3-en.html), [ORT Android](https://onnxruntime.ai/docs/build/android.html), [CTranslate2 build options](https://opennmt.net/CTranslate2/installation.html), [SentencePiece](https://github.com/google/sentencepiece), [fastText model](https://fasttext.cc/docs/en/language-identification.html).

### Specific build risks

- llama.cpp, whisper.cpp and OmniVoice carry their own ggml versions. Do not merge all static ggml into one library. Isolate inference modules in `.so` files, hide internal symbols with an export/version script and expose only the JNI/C ABI. Check symbol interposition and repeated loading of all engines in one process. Align the NDK and `libc++_shared.so` across all libraries.
- CPU is the mandatory path. Do not build the base with a global `-march=native` or optional Tensor/new Snapdragon instructions. Vulkan may not support some operations/FA or may create a second set of weights in RAM; this is checked on the device. NNAPI/QNN/NPU are not required dependencies of the first port.
- 16 KB compatibility is checked for **every** `.so`, including transitive ORT, Python and C++ runtime, and for ZIP packaging. NDK r28+ aligns ELF by default but does not fix third-party prebuilts. [Android 16 KB](https://developer.android.com/guide/practices/page-sizes).
- Proposed compatible toolchain: JDK 17, AGP 9.2.0, Gradle 9.4.1, NDK `28.2.13676358`, CMake 3.22.1, `compileSdk/targetSdk=36`, `minSdk=31`. This is a starting configuration, not a verified build. AGP 9.2 was chosen partly because Chaquopy 17 documents testing up to AGP 9.2; the Compose/Room/KSP Android plugins are pinned together after dependency resolution in stage 1, without `+`/`latest`. AGP 9 uses built-in Kotlin: do not add a second incompatible Kotlin Android plugin. [AGP matrix](https://developer.android.com/build/releases/agp-9-2-0-release-notes), [Chaquopy requirements](https://chaquo.com/chaquopy/doc/current/android.html).
- ML Kit is not accepted as an automatic replacement for the whole camera. The Android SDK documentation lists Latin/Chinese/Devanagari/Japanese/Korean dependencies; the general language list also mentions Cyrillic separately. RU/EN needs a reproducible test of a specific SDK/model, so the main plan is a full PP-OCR pipeline. If ML Kit is used later, take the bundled variant and check cold start without network. [Android OCR dependencies](https://developers.google.com/ml-kit/vision/text-recognition/v2/android), [language list](https://developers.google.com/ml-kit/vision/text-recognition/v2/languages).

## Models and file sizes

Sizes below come from the current code/manifests, in decimal MB/GB. This is **file size, not RAM usage**.

| Model / package | Download | Installed data / Android status |
|---|---:|---|
| **Index-Translate 9B Q4_K_M** | **5 780 090 304 bytes / 5.78 GB** | Same GGUF, 5.38 GiB; first mandatory device test |
| Whisper large-v3-turbo F16 | 1 624 555 275 bytes / 1.62 GB | Keep the baseline; pick a lighter Whisper only after a quality comparison |
| Piper Denis + LJ Speech | 183.01 MB of archives | 213.34 MB total by file manifests; shared data files may be deduplicated |
| Supertonic 3 INT8 | 128.77 MB | 145.32 MB; candidate for the main multilingual TTS after tests |
| Meta Omnilingual 300M INT8 | 292.31 MB | 366.71 MB; extra ASR languages, not all 1600 automatically available in Kat's UI |
| Wayu Thai | 331.72 MB | Three ONNX + voice packs; Python/runtime/data increase the total |
| OmniVoice Q8, base + codec | 945.28 MB | Two GGUF; a separate, complex porting branch |
| RU/EN OCR recognizers | 15.70 MB | Needs an additional detector, whose size is not included yet |
| fastText lid.176.ftz | Already bundled, 938 013 bytes | Small shared file; MIT for the code, CC BY-SA 3.0 for the model |
| OPUS Big INT8 | 492 650 422 bytes | Two directions; an additional stage, not the first MT |
| Parakeet Ultra `.mlmodelc` | Not downloaded on Android | Apple-only package |

Index keeps revision `d01404384ba429b93f5f63d43573812d103b5bcd`, SHA-256 `9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713`, a **2048** context window, a maximum request of **1536** and a response reserve of `ceil(sourceTokens * 1.5) + 64`. The original Chinese prompt and control tokens are kept; the actual tokenization of the pinned runtime is compared. Long text is split with a retry when the limit is exhausted; a success with a silently truncated answer is forbidden.

The [Index GGUF](https://huggingface.co/IndexTeam/Index-Translate-9B-GGUF) card states Apache-2.0. For voices, one license cannot be applied to the whole catalog: `additional-voices.json` includes CC BY-NC 4.0, CC BY-SA and individual notices. Keep the original per-file licenses and check the chosen distribution separately before publishing.

## Minimum system requirements

**These are initial engineering guidelines, not confirmed by Android measurements.** The public minimum is defined after the test matrix.

| Parameter | Initial threshold for Index | Recommended / main device |
|---|---|---|
| OS | Android 12 / API 31 | The OS actually installed on the Pixel 9 Pro; record before testing |
| Architecture | 64-bit OS, `arm64-v8a`, NEON; no mandatory NPU | Tensor G4; additionally Snapdragon and MediaTek |
| Physical RAM | **12 GB — experimental lower candidate** | **16 GB**; the Pixel 9 Pro has 16 GB per specification |
| Free storage | **15 GB** before the initial install of Index + Whisper + base voices | **20 GB** for updates/additional packages; computed before every download |
| GPU | Vulkan is needed for the main Index mode | Mali-G715 on the Pixel 9 Pro verified; other GPUs need tests |
| Microphone/camera | Only for the corresponding mode | Denying permission does not block text translation |
| Network | To obtain models/updates | After preparation, inference works offline, including after a restart |

Pixel RAM and processor: [Google's official specifications](https://support.google.com/pixelphone/answer/7158570?hl=en-GB5). Not all physical memory is available to a process. `largeHeap`, swap and mmap do not guarantee freedom from low-memory kills.

Initial estimate of the MT working set: roughly **7–10 GiB** with headroom for weights, KV, activations, runtime and UI; this is a hypothesis to measure PSS/RSS against, not a formula for exact consumption. Vulkan may change it in either direction. On a 12 GB device, start by unloading Whisper before Index and Index before TTS; on the Pixel use the same safe sequence first and keep engines resident only after measurements. Do not process 30 minutes of audio in one huge buffer: use chunking, bounded queues and files on disk.

8 GB devices are not declared supported for Index until a separate experiment succeeds. Replacing the main model with OPUS to lower the requirements does not match the current task.

Free space is computed by unique digest: missing blobs + temporary archives + unpacked data + the old version kept during an update + a reserve. A simple rename of `.partial` is not counted as copying the whole GGUF; the compressed tar.bz2 size is not the installed size. History and user recordings are added to this budget separately.

## Test plan and readiness criteria

1. **Contracts on the computer**: metadata integrity, no paths escaping the directory, unique paths, pinned Index/Whisper and runtime revisions. Automation is already added, but remote weights are not re-downloaded or re-hashed.
2. **Build/packaging**: Gradle unit tests, lint, NDK build, ELF/ZIP 16 KB checks, APK signature, ABI, versionCode; R8 release smoke test. Having a `.so` without calling a model is not enough.
3. **Native tests on Android**: Index load/tokenize/decode/cancel/unload with the real GGUF; tokenizer/prompt parity with Apple; ASR fixture → text; TTS → finite PCM samples and non-zero duration; OCR → text/boxes. Missing weights are an explicit FAIL for the acceptance job, not a green skip.
4. **Integration/UI**: airplane mode and a new cold start, denied permissions, pause/stop, rotation, background/return, audio focus, process killed by the system, Range resume, ETag change, disk full, wrong SHA, disabled history, empty and long text, stale callback after cancellation, recovery after an update.
5. **Quality and resources**: Pixel 9 Pro 16 GB + at least one ARM64 12 GB Snapdragon and one MediaTek/Samsung where available. The emulator is needed for API/lifecycle/16 KB; its speed is not counted as phone speed. 8 GB is a separate negative/experimental class.

For each device run, record the device model, API, ABI, page size, RAM/availMem, thermal status, backend, driver, build/runtime/model digest, cold/warm load, TTFT, tokens/s, end-to-end time, peak PSS/RSS and the termination reason. User text and voice are not included in shared telemetry; use agreed fixtures.

Preliminary Pixel acceptance criteria, still to be verified: 100 consecutive short translations without crash/ANR/success with truncation; a 20-minute alternating voice scenario without OOM; UI response to Stop ≤250 ms and the native job finishing within 2 s for a short test. For usability, measure warm TTFT and total time: target p95 ≤10 s to the first token and ≤30 s to translate a 20–40-word source. If Index is slower, show the actual result and optimize; do not declare these numbers achieved and do not swap the model. MT quality is assessed against agreed references/numbers/names and a manual bilingual sample, not by a single non-empty answer.

## What is checked now

`scripts/validation/android_readiness.py` and `test_android_readiness.py` were added; they use only the Python standard library.

```bash
python3 -m unittest discover -s scripts/validation -p test_android_readiness.py -v
python3 scripts/validation/android_readiness.py
# Once a real ARM64 APK exists:
python3 scripts/validation/android_readiness.py --apk dist/android/kat-translator.apk
```

The APK check verifies ELF64/AArch64, PT_LOAD and ZIP alignment ≥16 KB for uncompressed `.so` files, the presence of manifest/DEX and the absence of duplicate ZIP entries. This is a strict policy for our future ARM64 release, not a universal Android APK validator: compressed `.so` files are intentionally rejected. It does **not** check the signature, DEX/manifest correctness, completeness of JNI symbols, model execution, `DT_NEEDED` dependencies or real loading on a device; those are separate mandatory stages of the plan. The test APKs are synthetic and are not presented as the app.

Results of the run at that time: **31 tests pass; 7794 file entries in the existing JSON manifests checked**. The primary Index and two runtime commits are pinned. Negative tests confirm that replacing the primary with OPUS, changing the Index SHA or the llama commit is detected. `apk_packaging=NOT_RUN`, `android_inference_verified=false`. Logs: `.build/android-readiness/tests.log`, `.build/android-readiness/source-audit.json`. Existing Swift/Apple build tests were not run at that stage: the app sources were not changed. JDK/SDK/NDK and models were not installed at that point.
