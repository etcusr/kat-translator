# Android: installing Kat translator

**English** | [Русский](INSTALL.ru.md)

Whisper now includes a CPU path using FP16/dotprod instructions on compatible phones, with baseline arm64 fallback. Run `scripts/android/setup-media.sh` again before rebuilding: it prepares both libraries. The model remains large-v3-turbo F16; there is no smaller or quantized replacement. Auto still selects GigaAM/Parakeet; choose Whisper explicitly in Settings for its recognition quality. [Pixel measurements](benchmarks/2026-10-17-whisper-latency/README.md).

Current release: **0.4.6 / versionCode 21**, Debug, ARM64 / API 31+. APK: `dist/android/kat-translator-0.4.6-debug.apk`; the checksum is in `dist/android/SHA256SUMS`. Local artifacts are not part of Git. [Versions, results and limitations](../CURRENT_STATE.md).

Install over the previous app with the same application ID and signature, without deleting its data: this keeps models and history. Weights are not included in the APK. Downloading needs a network connection; translation, recognition and speech output run locally once the required packages are installed.

## First launch and model choice

1. On first launch, run the device check (about 3–5 s, CPU/Vulkan GPU, no model download), then choose your own languages and the translation languages.
2. The initial translation mode is "Auto". On a powerful device the installed Index 9B is used, then 2B; on other devices the installed OPUS package for the pair, then 2B and 9B. An explicit saved choice is not changed by an update.
3. Review the package plan and total size on the "Your languages" screen and download what is needed. If everything is already installed, "Download" is disabled and "Done" saves the selection.
4. In "Models" you can choose an engine manually. "OPUS directions" lets you search languages and pick individual directions with a combined download size. Of the 54 packages, 10 are downloadable; 44 are marked for manual installation until hosting is available. Exact pairs are defined by `assets/catalogs/opus-direction-packages.json`.
5. In "Text" choose a pair and enter text; "Voice" offers recording and audio import; "Camera" takes a photo or opens an image. Voice and camera need an explicit source language; text auto-detection stays available.

OPUS uses CTranslate2 CPU INT8: the legacy EN↔RU/UK/BE package and the new direct directions, including pairs without English. There is no hidden pivot. Index 2B (1 312 164 352 bytes) and 9B (5 780 090 304 bytes) use GGUF Q4_K_M on Vulkan; MTP is applied only to 9B. Sizes, SHA-256 and URLs come from the shared catalogs. Spot checks showed 2B ahead on speed and 9B ahead on quality; this is not an acceptance of every language.

Model preparation includes file verification and weight loading. With automatic loading turned off, manual preparation is available; memory saving unloads the model after use. Cancelling must leave the app ready for the next request. The original recording and the TTS output are saved and shared separately; playback normalization of up to 32× does not change the raw PCM used for recognition.

## Recognition and images

ASR "Auto" routes Russian → GigaAM v3 and the other 24 languages of the 25-language Parakeet catalog → Parakeet TDT v3. If a required package is missing, the app offers to download it. A manual model choice takes priority. Other languages have separate Android on-device/Whisper/Meta paths; there is no cloud fallback. "Auto" in the ASR settings selects an engine, not a language. System PCM import needs Android 13+ and an available on-device service.

OCR: bundled ML Kit for supported scripts, Russian via PP-OCRv5 eslav with the mobile detector; compatibility with the older installed detector is kept. Choose the language before taking the photo. Apple Core ML/Vision are not Android backends.

## Verified devices and limitations

Reports refer to a Pixel 9 Pro, Android 17 / API 37, 16 GB RAM, 4 KB pages. For Index, the CPU part of the runtime requires ARMv8.2 dotprod/FP16; unsupported devices are rejected by a HWCAP check. Index uses Vulkan; real devices with 16 KB pages, minimum RAM on weaker phones and other GPUs still need checking. In-app network download of 2B is not confirmed yet: the test used an import.

[Auto](benchmarks/2026-10-13-auto-translation/README.md) · [OPUS directions](benchmarks/2026-10-13-opus-directions/README.md) · [Index 2B](benchmarks/2026-10-12-index2b-default/README.md) · [ASR](benchmarks/2026-10-12-asr-routing/README.md) · [historical feature matrix](FEATURE_PARITY.md). A successful build and the presence of an implementation do not prove quality for every language or full parity with iOS.

## Building on Apple Silicon

```bash
python3 scripts/android/setup-tools.py
python3 scripts/android/setup-vulkan-tools.py
bash scripts/android/setup-media.sh
bash scripts/android/setup-opus.sh
bash scripts/android/setup-omnivoice.sh
python3 scripts/android/setup-wayu.py
scripts/android/build.sh
source scripts/android/env.sh
export ANDROID_SERIAL=<serial-from-adb-devices>
scripts/android/test-parity.sh ui
scripts/android/test-parity.sh opus
```

Tools are stored locally in `.build/android-tools`. Versions are pinned in
`Dependencies/android-runtime.lock.json`; shaderc/headers are verified by
SHA-256 in the setup script, Maven artifacts by `gradle/verification-metadata.xml`.
Vulkan is built with the NDK and a modern local host shader compiler.
The patch is applied to a copy of the source in the build directory; the shared vendor tree is not changed.

Device tests need an authorized phone and a real model; a missing model counts
as a failure. They check the tokenizer/Unicode, directions, repeated GPU
requests, limits, cancellation followed by a new request, engine reload,
screens, rotation and history persistence. Do not run them while translating
manually: instrumentation controls the Kat process.

Profiling: `bash scripts/android/profile-index.sh <new-label> -e profile gpu`.
For plain timing, drop `profile gpu`: GPU timestamps add synchronization and
distort latency. `-e corpus true` enables five different texts. For a single
text: `-e corpus true -e corpusOnly true -e corpusCase medium-en-ru`.
`-e stockPrefill true` restores the 0.2.1 input processing; `-e stockMmvq true` restores the previous kernel for A/B comparison.

This is a test Debug build. A public signed release has not been prepared yet;
the Debug signing key is not the key of a future release.
