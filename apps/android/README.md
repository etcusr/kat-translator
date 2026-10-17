# Android app

**English** | [Русский](README.ru.md)

Piper starts playback from generated fragments; one Whisper model and one Piper voice stay cached on sufficiently large-memory devices. Voice loading can overlap translation. Stop discards pending playback, while completed audio stays available for replay/export. Partial translation speech is still a separate future step. [Implementation, timings and limits](../../docs/android/benchmarks/2026-10-17-streaming-cache/README.md). On the 28.86-second Pixel fixture, first playback changed from 25.61/25.28 s to 20.34/17.95 s (cold/repeat); recognition text and translation matched exactly. These are recorded observations, not a general latency guarantee.

VITS/Piper speech uses up to four CPU threads with unchanged model/voice settings. On Pixel, a measured 257-character synthesis fell from 17.38 to 10.42 seconds. Other devices require their own measurements. [Timing breakdown and checks](../../docs/android/benchmarks/2026-10-17-tts-latency/README.md).

Voice mode shows both original and translation cards immediately; the original stays expanded. The active speaker button becomes a stop cross during playback, including automatic speech, and returns after stopping or completion. Verified on Pixel with 4 device tests. [Verification](../../docs/android/benchmarks/2026-10-17-voice-results/README.md).

Current build: **0.4.6 / versionCode 21**, Debug, ARM64 / API 31+. Verified platform: Pixel 9 Pro / Mali-G715. [Overall current state](../../docs/CURRENT_STATE.md).

Kotlin/Compose: Voice/Text/Camera, languages, history, settings, models, downloads, audio and the shared animations. The initial choice is "Auto": installed Index 9B → 2B on a powerful device, a supported OPUS direction → 2B → 9B on the others. Available engines: OPUS Big via CTranslate2 CPU INT8 (the EN package and separate directions), Index 2B Q4_K_M on Vulkan without MTP and Index 9B Q4_K_M on Vulkan with MTP. A saved manual choice is kept.

ASR Auto: Russian → GigaAM v3, the other Parakeet-supported languages → Parakeet TDT v3; a missing required package is offered for download. A manual choice takes priority. Voice and camera need an explicit source language; text Auto stays available. OCR: bundled ML Kit for supported scripts, Russian via PP-OCR.

Catalogs: `../../assets/catalogs`; models/voices: `../../model-store`. Weights are not part of the APK. Native C ABI: `../../shared/native`. Mali Q6 and other Android-only patches are applied to a build copy without changing the shared vendor/Apple Metal code.

[Install and build](../../docs/android/INSTALL.md) · [Architecture and porting history](../../docs/android/README.md) · [Historical Q6 check](../../docs/android/benchmarks/2026-10-12-mali-q6-kernels/README.md) · [ASR routing](../../docs/android/benchmarks/2026-10-12-asr-routing/README.md).
