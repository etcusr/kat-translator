# Kat translator

**English** | [Русский](README.ru.md)

**iOS 1.0.1 (58), 20 October:** the package with Whisper Q8, diagnostic audio import and updated recording defaults is verified and uploaded to Apple. Four release-note localizations were saved and reread exactly; manually revised keywords were preserved and synchronized to the documentation. Build 58 was processed, selected and submitted: **Waiting for Review**, confirmed at 23:23 Moscow time. Manual release remains selected. Sources, including completed Mac changes, were pushed to GitHub (`f24ddb0`). [Evidence](docs/publication/ios-q8-store-2026-10-20.md).

**iOS recording defaults:** Whisper date/time repair is enabled and automatic stop uses 3 seconds of silence when no saved preference exists. Explicit saved choices are preserved. macOS/Android defaults are unchanged.

**Earlier iOS Store update, 20 October (superseded by build 58):** **1.0.1 (57)** was verified and uploaded, with progressive Index 9B Text/Voice output and improved download Live Activity updates. 144 repository checks and distribution-package validation passed; prior device retention/partial-text acceptance is documented separately. Build 57 is processed and selected for version 1.0.1 in App Store Connect, with saved AI descriptions and release notes in EN/RU/ES/TR. Review cancelled on 20 October for metadata revisions: Developer Rejected; build 57 retained, manual release unchanged. No new macOS Store upload; Mac metadata changes are deferred in BACKLOG. [Release evidence](docs/publication/ios-store-update-2026-10-20.md).

**iOS 1.0 (55) was verified and uploaded to App Store Connect** with the original-recording volume fix. The owner checked development 54 and reported that it appears correct; that was the installed build at that earlier checkpoint. Signatures, IPA contents and 143 project checks passed. Apple processing and Store 55 installation through TestFlight are unconfirmed; the owner selects the App Review build. Local Store 53/54/55 distributions are retained. [Checks and upload](docs/publication/ios-original-volume-2026-10-18.md).

Local DMG/ZIP packages are updated to **0.6.8 (61)** for macOS 27+ and separately macOS 15–26. Both include the current recognition/speech and Image fixes, including paragraphs and diagnostic timings. Extracted contents, signatures, checksums and library deployment limits passed verification. Keep at most three releases per line: modern 59/60/61, compatible 53/61 (only two exist). The corrected installed copy remains 0.6.7 (60). [Package checks](docs/publication/mac-direct-2026-10-18.md).

**iOS 1.0 (54) and Mac App Store 1.0 (76)** were verified and uploaded to App Store Connect. They include recognition preparation before the microphone, recognition release on Text/Camera, and the off-by-default date/time correction setting. iPhone AudioQueue capture reduces first-buffer latency from about 1.40 to 0.28 seconds in development-device measurements. During-recording processing and prior streamed-speech fixes are preserved. Mac also reconstructs OCR paragraphs and shows recognition/translation timings when diagnostics is enabled. Signatures, entitlements, resources and all 143 project checks passed. Apple processing and TestFlight installation are not yet confirmed; the owner selects builds for App Review. [Verification and upload](docs/publication/apple-capture-store-2026-10-18.md).

**Previous upload, 17 October:** **iOS 1.0 (53) and Mac App Store 1.0 (71)** were built from the corrected sources, verified and uploaded to App Store Connect. They include complete streamed speech, exact whitespace handling to avoid replay, contextual Russian ordinals and Mac MLX partial output. Both packages contain the current 13 loading clips. Project validation: 143 PASS. Apple processing, TestFlight installation and build selection for review are not yet confirmed. [Checks and upload result](docs/publication/apple-speech-store-2026-10-17.md).

The microphone defaults to tap to start / tap to stop on iOS, macOS and Android. On iOS, first-run language setup recommends Whisper large-v3-turbo Q8 (874.2 MB) for Whisper-supported languages. Updating requires a one-time download of this new asset; previous F16 weights, other models, settings and history are retained. With technical information enabled, Voice offers **Open audio file** for diagnostic recognition/translation, respecting the automatic speech switch. Native Whisper uses Metal without Core ML. A saved recording-mode choice is preserved; hold to record remains available in Settings. The current iOS54/Mac76 store packages and refreshed direct Mac build include this default.

**GPL-3.0-or-later.** Copyright (c) 2026 the respective copyright holders of Kat translator. Kat's own code may be used, modified and redistributed under GNU GPL version 3 or any later version, without warranty. Third-party components and models retain their own licenses. [GPL text](LICENSE) · [License scope and distribution terms](docs/LICENSING.md).

An offline AI translator for voice, text and image text for **iPhone, Apple Silicon Mac and ARM64 Android**. Processing runs on the device after the required models have been downloaded. Speech recognition, translation and speech synthesis are separate stages; availability and quality depend on the language, model and device.

**Start here:** [current status](docs/CURRENT_STATE.md) · [RU/EN product description](PROJECT_DESCRIPTION.md). This overview was checked against the working tree on October 14, 2026. Dated reports describe the build tested at that time, not necessarily today's code. Living documentation is in English with Russian versions (`*.ru.md`); dated reports stay in their original language. [Documentation index](docs/README.md).

iOS **1.0 (52)** packages the microphone and memory-pressure fixes, tap recording defaults and the current 13 loading clips. Package validation and upload passed; TestFlight acceptance is tracked in the [release report](docs/publication/ios-store-build52-2026-10-17.md).

Earlier iOS **1.0 (51)** and Mac **1.0 (70)** passed package verification and were uploaded to App Store Connect, with the playback fix, signed SDK distributions, nine manifests and 46 license documents. 138 validation tests passed. Build selection, TestFlight and review submission remain with the owner. [Verification and remaining work](docs/publication/signed-sdks-release-2026-10-14.md).

The iPhone playback fix passed six device regressions and two repeated voice cases; the shared Mac player also passed. Release 51/70 includes this fix. [Evidence and limits](docs/publication/ios-playback-fix-2026-10-14.md).

Local runtime checks now include sandboxed Mac inference with network access denied. iPhone downloads and final voice repeats passed, but intermittent playback failures and a Thai pipeline timeout remain unresolved. [Runtime results and limits](docs/publication/runtime-acceptance-2026-10-14.md).

**Repository privacy:** personal recordings, transcripts and diagnostic media are excluded from the published history. [Scope and handling of local data](docs/REPOSITORY_PRIVACY.md).

## Features

- Voice input, audio import, text translation, phone cameras and images on Mac.
- Local ASR → MT → TTS, model and voice selection, package downloads and verification.
- Language lists, search and favorites, with separate state for each working mode.
- History of text, original recordings, synthesized speech and images, depending on settings.
- Original and translated audio playback, pause/speed controls, copying and system sharing.
- Russian, English, Spanish and Turkish interfaces. Mac also supports keyboard shortcuts and translation of selected text, clipboard contents and screen regions.

The main voice workflow processes a recording after it stops. Recognition previews do not imply verified simultaneous conversation translation. Speed, quality and features are not guaranteed to be identical across all three platforms.

## Models and platform differences

| Stage | iPhone | Mac, modern release | Android |
|---|---|---|---|
| Index-Translate 9B | llama.cpp / Metal, Q4_K_M, MTP2 | MLX 4bit + MTP2 | llama.cpp / Vulkan, Q4_K_M, MTP; Mali-G715 profile |
| Index-Translate 2B | llama.cpp / Metal, Q4_K_M | separate llama.cpp / Metal, Q4_K_M | llama.cpp / Vulkan, Q4_K_M, no MTP |
| OPUS Big, EN↔RU/UK/BE | CTranslate2 CPU INT8 | separate Python / PyTorch Metal FP16 worker, beam5 | CTranslate2 CPU INT8 |
| OPUS directions from the catalog | CTranslate2 CPU INT8 | CTranslate2 CPU INT8 | CTranslate2 CPU INT8 |
| Auto ASR | Whisper Q8 / Metal; Meta for additional languages | Whisper F16 / Metal; Meta for additional languages | RU → GigaAM v3; other Parakeet-supported languages → Parakeet TDT v3; separate existing paths for others |
| OCR | Apple Vision + local OCR routing | Apple Vision + local OCR routing | bundled ML Kit for supported scripts; PP-OCR for Russian |
| Initial MT selection | Auto | Auto | Auto |

On iOS, initial language setup recommends Whisper large-v3-turbo Q8 (874.2 MB) for Whisper-supported languages. Existing installations download this new asset once; old F16 files, other models, settings and history are retained. With technical information enabled, Voice exposes **Open audio file** for diagnostic recognition/translation using the existing automatic-speech switch. The native Whisper runtime uses Metal without Core ML.

Updates preserve the saved model selection. Auto chooses an installed model for the language pair based on the device test: 9B, then 2B on powerful devices; supported OPUS, then 2B and 9B on others. The older OPUS EN package translates **EN↔RU/UK/BE**; the direction catalog adds direct pairs, including pairs without English. There is no hidden pivot translation. Of 54 direction packages, 10 are available for download and 44 require manual installation until hosting is available. Index has broad text-language coverage; this does not establish quality for every pair or equivalent ASR/TTS/OCR coverage. Model and license sources: [assets/catalogs](assets/catalogs), [publication package inventory](docs/publication/2026-10-12/evidence/model-inventory.csv).

Mac `macos15-26` is a separate retained release with Index MLX+MTP2 and the earlier CPU OPUS implementation. It has not received GPU OPUS, Index 2B, the new directions, Auto translation or later interface changes from the modern release. [Versions, operating systems and verification limits](docs/CURRENT_STATE.md).

Index uses a fixed 2048-token context window with up to 1536 input tokens; the response uses the remaining space. Budget estimation and splitting guard against overflow. Experimental context memory and window selection have been removed. OPUS has separate limits and splitting. [Preflight](docs/benchmarks/translation-preflight/README.md) · [OPUS](docs/IMPLEMENTATION-opus-big.md).

## Repository layout

| Path | Purpose |
|---|---|
| `apps/ios`, `apps/macos`, `apps/android` | Platform apps, projects and tests |
| `shared/apple` | Shared SwiftUI screens, AppModel and Apple adapters |
| `shared/packages/OfflineCore` | Swift data models, pipeline, storage, policies and tests |
| `shared/native` | C/C++ runtimes and Python workers |
| `assets/catalogs`, `assets/bundled` | Package catalogs and small shared resources |
| `model-store` | Shared local model cache, excluded from Git |
| `Dependencies` | Pinned versions, vendor sources and build dependencies |
| `scripts`, `tests`, `Tools` | Builds, diagnostics, shared fixtures and local import |
| `docs`, `.build`, `dist` | Documentation; local outputs; installers |

[Detailed layout](docs/android/PLATFORM_LAYOUT.md). The old `App/`, `Packages/` and `Native/` paths in earlier documents predate the migration. Source code is in Git; model weights, installers and local data are stored separately. Check the working tree and current versions before making changes.

## Build and validation

The build host is an Apple Silicon Mac with Xcode, CMake/Python and prepared pinned dependencies. These are not end-user requirements. Model weights and the complete environment are not included in Git. Run the commands below from the repository root; building does not install the app.

```sh
# Shared Swift policies
swift test --package-path shared/packages/OfflineCore --scratch-path .build/core
# Catalog consistency
python3 scripts/generate-model-catalog.py --check
# iPhone: native dependencies must already be prepared
python3 scripts/generate-project.py
xcodebuild -project apps/ios/OfflineTranslator.xcodeproj -scheme OfflineTranslator \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Apple dependency preparation: `scripts/build-whisper.sh`, `scripts/build-translation.sh`, `scripts/fetch-speech-runtime.py`, `scripts/prepare-speech-recognition.py`; additional runtimes depend on the selected configuration. Full platform instructions: [Mac](docs/macos/README.md), [Android](docs/android/INSTALL.md), [current status](docs/CURRENT_STATE.md).

Xcode generators define project membership. Local iOS signing settings live in `apps/ios/Config/Signing.local.xcconfig` (ignored). Since October 14, the iOS Bundle ID is `app.kattranslator`, with `app.kattranslator.downloads` for the extension. Build46 with the new ID is installed; models, history and settings have been migrated and verified. The old app is retained separately. [Results and limitations](docs/maintenance/ios-kat-migration-2026-10-14.md). Preserve bundle IDs, signing identity, models and data during ordinary updates. Build numbers increase independently; versions change during release preparation. After an iOS version change, the generator synchronizes the widget version.

Hardware tests are separate from unit tests and compilation. Do not run instrumentation alongside manual translation or another intensive experiment on the same device. [Current results and remaining checks](docs/CURRENT_STATE.md).

## Documentation

- [Documentation index](docs/README.md) — all living documents in English and Russian.
- [CURRENT_STATE](docs/CURRENT_STATE.md) — current versions, implemented changes, limitations and evidence.
- [Publication queue](docs/publication/OPEN_QUESTIONS.md) — what remains before App Store / Google Play publication.
- [Architecture](docs/ARCHITECTURE.md) — components, key files and builds.
- [Android](docs/android/README.md), [Mac](docs/macos/README.md), [iPhone testing](DEVICE_TESTING.md).
- [Publication preparation](docs/publication/2026-10-14/README.md) — dated preparation materials, not a published app.
- [Animations](docs/branding/loading-animations/README.md), [branding](docs/branding/README.md).
- [Previous README](docs/history/README-before-2026-10-12-sync.md) — archived details of earlier iterations.

Dependency source delivery and SDK provenance are documented [here](docs/licensing/2026-10-14/publication-and-sdk.md). The source tree now includes 46 notice documents; the newly rebuilt/signed Opus SDK is a separate candidate for the next release.

Release 51/70: three verified upstream speech SDK distributions now carry Kat signatures, with unchanged payloads and corrected embedded-commit/source mapping. The release includes the audio-session fix and 46 notices. [Build, validation and upload status](docs/publication/signed-sdks-release-2026-10-14.md).
