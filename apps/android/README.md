# Android app

**English** | [Русский](README.ru.md)

Voice mode shows both original and translation cards immediately; the original stays expanded. The active speaker button becomes a stop cross during playback, including automatic speech, and returns after stopping or completion. Verified on Pixel with 4 device tests; synthesis speed is unchanged. [Verification](../../docs/android/benchmarks/2026-10-17-voice-results/README.md).

Current build: **0.4.6 / versionCode 21**, Debug, ARM64 / API 31+. Verified platform: Pixel 9 Pro / Mali-G715. [Overall current state](../../docs/CURRENT_STATE.md).

Kotlin/Compose: Voice/Text/Camera, languages, history, settings, models, downloads, audio and the shared animations. The initial choice is "Auto": installed Index 9B → 2B on a powerful device, a supported OPUS direction → 2B → 9B on the others. Available engines: OPUS Big via CTranslate2 CPU INT8 (the EN package and separate directions), Index 2B Q4_K_M on Vulkan without MTP and Index 9B Q4_K_M on Vulkan with MTP. A saved manual choice is kept.

ASR Auto: Russian → GigaAM v3, the other Parakeet-supported languages → Parakeet TDT v3; a missing required package is offered for download. A manual choice takes priority. Voice and camera need an explicit source language; text Auto stays available. OCR: bundled ML Kit for supported scripts, Russian via PP-OCR.

Catalogs: `../../assets/catalogs`; models/voices: `../../model-store`. Weights are not part of the APK. Native C ABI: `../../shared/native`. Mali Q6 and other Android-only patches are applied to a build copy without changing the shared vendor/Apple Metal code.

[Install and build](../../docs/android/INSTALL.md) · [Architecture and porting history](../../docs/android/README.md) · [Historical Q6 check](../../docs/android/benchmarks/2026-10-12-mali-q6-kernels/README.md) · [ASR routing](../../docs/android/benchmarks/2026-10-12-asr-routing/README.md).
