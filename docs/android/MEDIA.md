# Android offline media runtime

**English** | [Русский](MEDIA.ru.md)

Android now has native adapters for the existing shared Whisper F16 model,
Piper/MMS and Supertonic voices, Meta Omnilingual, Silero VAD, and PP-OCR ONNX
recognizers plus a new shared PP-OCR detector package. All inference uses local
files. The app-owned media engines do not use platform TTS or online recognition.
A separate on-device SpeechRecognizer adapter now handles automatic system
ASR when available; real Pixel RU/EN and ASR→OPUS tests pass. See
research/platform-speech.md for requirements, timings and limitations.

`bash scripts/android/setup-media.sh` verifies the official sherpa-onnx 1.13.8
Android archive, extracts only the two arm64 libraries, fetches digest-pinned C
headers, then builds the already-pinned Whisper source with NDK28.2. The lock is
`Dependencies/android-media.lock.json`. Do not substitute the Apple libraries.
The downloaded ONNX Runtime reports1.28.2, so the lock intentionally differs
from Apple's1.28.1. Both downloaded libraries have16KB ELF LOAD alignment.

Whisper has a separate hidden-symbol DSO and its own pinned ggml. Index's ggml
and Vulkan policy are unchanged. Android Whisper currently uses4 CPU threads;
this is an explicit ASR backend choice, not an Index GPU fallback. The shared
Whisper turbo F16 file is consumed directly, without conversion or duplication.
Whisper options match Apple's greedy, no-context, zero-temperature transcription.

CMake includes `media.cmake`; Gradle packages its imported library dependencies.
Only `Java_org_openoffline_translator_inference_MediaNative_*` is exported from
new native wrappers. The loader uses standard UTF-8 byte arrays, including emoji
and combining characters; it rejects embedded NUL. Cancellation flags have
shared C ownership and remain live until the synchronous native call returns.
Each media operation loads and unloads its model; the UI must unload Index and
serialize large operations to avoid overlapping memory use.

## APIs

All classes are in `org.openoffline.translator.inference`.

- `OfflineMedia.transcribe(modelPath, samples, language="auto")`: mono16kHz float
  PCM to `Transcript(text,language)`. Selected unsupported Whisper languages fail.
- `transcribeOmnilingual(modelPath,tokensPath,samples,language)`: same PCM contract.
  Language is caller-selected; the engine does not supply reliable auto detection.
- `synthesizePiper(model,tokens,dataDir,text)` and
  `synthesizeSupertonic(directory,text,language)`: `SpeechAudio(samples,sampleRate)`.
  MMS uses the VITS/Piper adapter with its catalog paths and empty data directory.
  Supertonic uses the seven existing package files and shared31-language check.
- `recognize(bitmap,detectorPath,recognizerPath,dictionary)`: normalized top-left
  `OcrBlock` boxes and CTC-decoded text. Dictionary is the shared transformed JSON.
- `cancel()` is safe during an operation; `close()` waits for the worker.
- `PcmRecorder(vadModelPath?)`: microphone permission required before `start()`;
  `pause()/resume()/stop()`, finite30-minute limit, `rms`, `elapsedMillis`,
  `speechDetected`, `lastSpeechMillis`, `failure`. With the bundled Silero path,
  `speechDetected/lastSpeechMillis` come from model inference, not amplitude alone.
  Pauses do not count toward recorded duration. Recording is foreground-only.
- `SpeechPlayer(context)`: float streaming playback with actual engine rate,
  speed0.5–2x, pause/resume/stop and Android audio focus. `exportWav`/`writeWav`
  exports existing PCM16 WAV without re-synthesizing or sharing source weights.

## Verification and current limits

Native arm64 Whisper and media wrappers compile independently. Kotlin compiles.
JVM fixtures cover CTC Unicode/repeated characters, dictionary mismatch, detector
noise/geometry, finite PCM and WAV header/rate/duration. Instrumentation boundary
cases cover library load, cancellation flags, corrupt Whisper and missing OCR.
Root integration owns device execution; a host build is not a speech quality,
real-camera, routing, thermal endurance or device latency result.

PP-OCR detector preprocessing is BGR/ImageNet normalization with dimensions
rounded to32 and max side960. Connected probability components become padded,
axis-aligned boxes. This is functional horizontal-text detection, but not full
Paddle contour/unclip/rotated-rectangle parity. Perspective correction, automatic
orientation detection, block grouping and overlay quality still need device
fixtures. The UI must provide manual rotate/crop where needed. OCR and
Omnilingual ORT calls cannot be interrupted midway; cancellation drops their
result after that call returns. TTS cancellation occurs at the shared sherpa
callback boundaries. Whisper model loading is likewise not interruptible. Android now forwards
Whisper abort callbacks into every GGML scheduler backend (conv/encoder/cross/
decoder), using a fail-closed generated source patch; the vendor/Apple sources
remain unchanged. Previously the scheduler overload only checked cancellation
after the full encoder. The Pixel UI cancellation regression returned idle in
628 ms and accepted a subsequent OPUS request. Cancellation before native start
is also carried across the Java flag-publication boundary.

## Additional shared voices

OmniVoice now uses the exact shared vendor revision53e6c206 and cancellation
patch, separate own-ggml Android DSO, same Q8_0 model+codec and five-second
chunks. `bash scripts/android/setup-omnivoice.sh`, then include `omnivoice.cmake`
after `media.cmake`. API: `synthesizeOmniVoice(directory,text,language)`,24kHz.
Its explicit current Android backend is CPU; Index remains Vulkan. The exact
shared OmniVoice package passed real Pixel 9 Pro synthesis on 2026-10-12
(build14): the Malay fixture `Terima kasih.` produced 40,320 finite samples at
24 kHz (1.68 seconds), energy 1874.166, with 87.559 seconds of synthesis/load
work. It is available as an experimental voice; even a short phrase can take
over a minute, and this test does not establish native-speaker pronunciation
quality for every catalog language.

Wayu reuses the same C+ORT acoustic runtime and unchanged prepared Thai frontend
(TLTK/PyThaiNLP/lexicon). `python3 scripts/android/setup-wayu.py` verifies the
[official Python3.14.8 Android archive](https://www.python.org/downloads/release/python-3148/),
then packages stdlib plus shared frontend as a14.1MB APK asset ZIP,1527 files.
The dependency lock pins both the published archive and unpacked content tree.
The acoustic model files remain in the existing shared downloaded voice package.
Include `wayu.cmake` after `media.cmake`, and add `.build/android-media/assets`
to the app asset source directories. The four Python runtime DSOs are imported
through CMake; all their LOAD segments and extension modules checked16KB aligned.

`WayuAssets.prepare(context)` verifies and installs only the APK-shipped runtime
to noBackupFilesDir. Then call `synthesizeWayu(runtimeDirectory,directory,text,
voice)`; default voice `m_elderly_deep`, all12 existing voices are exposed by
`OfflineMedia.wayuVoices`. Text is passed as a Python string, never evaluated.
Code cannot be supplied by a downloaded voice package. Embedded Python is
initialized once for the process, while acoustic sessions unload per operation.
The native Android frontend initializer replaces Apple's executable-path and
framework include logic only. Host Python3.14 frontend fixtures6/6 pass; native
arm64 optional engines compile. `WayuDeviceTest` verifies identical Thai/English
phoneme IDs and number normalization on the actual embedded interpreter.

Device execution, real optional-voice synthesis, listening quality and memory
endurance remain separate integration acceptance. Apple-only CoreML is not an
Android backend. No full iOS feature parity or WER/CER/listening quality claim
follows from compilation alone.

## Selective real-model acceptance

`MediaPipelineTest` has separate `asr`, `piper`, `supertonic`, `ocr`, `wayu`,
`omniVoice` methods for the root thermal runner. The class never starts downloads
or changes preferences/history. It waits for PackageRepository's catalog hash
verification, leases the exact package, and reports backend identity/output
metrics. ASR uses the test-only synthetic LJ Speech WAV fixture and asserts
negation/order/train words; OCR creates HELLO WORLD with Android Canvas. Voice
checks require finite, non-silent PCM with the actual engine rate and save WAV
for listening. Voice PCM checks alone do not establish pronunciation quality.

Package paths are under Android external files `packages/`: single-file packages
use `<id>.bin`, multipart/archive packages use `<id>/` with exact manifest names.
Whisper ID is `whisper-large-v3-turbo-f16`; OCR IDs `ppocr-v5-det` and
`ppocr-v5-english`; voices `vits-piper-en_US-lessac-medium`,
`sherpa-onnx-supertonic-3-tts-int8-2026-05-11`, `wayu-prosody`,
`omnivoice-q8-base`. Wayu renames its four downloaded files to the existing
catalog's `wayu-prosody.bin`, `wayu-curves.bin`, `wayu-decoder.bin`,
`wayu-styles.bin`; this is a filename mapping, no weight conversion.

For a developer device fixture import, `scripts/android/install-media-fixtures.py`
first verifies the selected host files against the shared catalogs. Its default
mode only prints a plan. Explicit `--install` stages under `/data/local/tmp`,
then runs `AppOwnedPackageFixtureTest#importExactSharedPackage` to verify and
publish files with app-context ownership. Never create the app's external package
directories using shell or `run-as`: the tested FUSE storage namespace rejects
those paths. `--source ID=PATH` selects an existing shared file or directory;
Index is excluded. Root must serialize imports with all device tests.

MMS text uses the shared no-word-dropping contract in `MmsSpeechText`: NFC,
lowercase, explicit token vocabulary validation, restricted native number
spellout and rejection of English ICU fallback. The pinned public
`com.ibm.icu:icu4j:78.3` dependency supplies `RuleBasedNumberFormat`; Android's
SDK does not expose that class. Version verified against
[Maven Central metadata](https://repo.maven.apache.org/maven2/com/ibm/icu/icu4j/maven-metadata.xml),
API against the [official ICU docs](https://unicode-org.github.io/icu-docs/apidoc/released/icu4j/com/ibm/icu/text/RuleBasedNumberFormat.html).
`MediaLanguageDeviceTest` and the host JVM tests verify Tamil spellout and
rejection of fallback. The Tamil `12` golden is the exact cardinal rule in
[ICU release-78.3 ta.txt](https://github.com/unicode-org/icu/blob/release-78.3/icu4c/source/data/rbnf/ta.txt#L32),
also checked by running that pinned JAR on the host.
ICU4J 78.3 lacks the Apple number rules for Bengali,
Kannada, Punjabi and Marathi; digits in these languages currently require
spelling out in words. Arbitrary letters or unsupported numbers fail before
synthesis instead of silently disappearing.

## Live Android camera

`org.openoffline.translator.android.camera.LiveCamera` uses Camera2 directly,
with a real TextureView preview, rear-camera continuous focus, tap metering and
bounded digital zoom. It emits upright YUV OCR frames at most every 350 ms,
max side 1600, with one outstanding `CameraFrame` until the consumer closes it.
Late frames and photos are invalidated by session generation. A shutter captures
JPEG through a separate ImageReader; ImageDecoder applies EXIF once and bounds
its upright bitmap to 3072. No frame is written to disk by the helper.

All public methods and callbacks use the main thread; camera sessions, YUV
conversion and JPEG decode use the private handler. UI owns CAMERA permission,
`start`, lifecycle `stop`, and disposal `close`. UI must close every CameraFrame
in a worker finally block, disable frame delivery during other native work, and
own/recycle the Bitmap returned by `capture`. `stop` releases session, readers,
surfaces and camera; `close` also unregisters display callbacks and quits its
handler. Source APIs follow [Camera2 preview](https://developer.android.com/media/camera/camera2/camera-preview)
and [ImageDecoder](https://developer.android.com/reference/android/graphics/ImageDecoder).

`ImagePerspective.rectify` accepts four explicit normalized corners (clockwise,
top-left first) for a frozen/imported photo and maps them to a bounded rectangle.
It validates convexity and rejects crossing/degenerate points. This is explicit
user geometry, not an automatic document detector. OCR paragraph grouping now
uses the same thresholds as shared `HybridOCR.swift`. Apple's broader Vision
language coverage is still not an Android engine; Android routes only to actual
installed catalog recognizers.

Tests: CameraGeometryTest covers orientations, inverse mapping, crop-aware focus,
YUV color and invalid perspective points. CameraPixelsDeviceTest uses generated
pixels for JPEG bounds, rectangle correction and frame ownership.
LiveCameraDeviceTest requires root-granted CAMERA and exclusive hardware: real
preview, photo, paused delivery and stop/reopen. It neither saves nor logs pixels.

Wayu Android initialization originally failed because CPython could not find
`Asia/Bangkok` in a POSIX timezone directory. The asset now includes the complete
first-party `tzdata` 2026.5 wheel (pinned SHA in the media lock), including licenses.
This follows the [standard zoneinfo fallback](https://docs.python.org/3/library/zoneinfo.html#data-sources);
no Thai frontend logic or timezone offset was substituted. A host run with empty
`zoneinfo.TZPATH` verified the bundled Bangkok data and all six shared frontend
fixtures. Device frontend acceptance must still be repeated with the new APK.

## OmniVoice baseline ARM64 correctness

The pinned GGML helper `ggml_vdotq_s32` grouped products differently from SDOT
when compiled without DOTPROD. Although its integer total was equal, its lane
values differed. Q8 floating-point accumulation then produced different MaskGIT
tokens: the exact shared Malay fixture `Terima kasih.` decoded to approximately
`2.25e-5` raw energy on Pixel and silence removal correctly rejected it.

`omnivoice_cpu_compat.h` overrides only this helper in OmniVoice's private
`ggml-cpu` target. Pairwise widening sums now preserve the four contiguous
products in each SDOT lane. This uses baseline ARM64 NEON, does not require
DOTPROD/FP16 extensions, and leaves Index, Whisper, shared vendor sources and
both original Q8 GGUF files unchanged. Setup checks the pinned fallback anchor
before applying the adapter.

Controlled host results with the same models, seed and text:

| CPU configuration | Token hash | Raw audio energy | Result |
| --- | --- | ---: | --- |
| Apple default ISA, no BLAS/Accelerate | `1c7090618c51ce37` | 3341.73 | 1.68 s audio |
| Baseline ARMv8-A | `1eac351f3cbaa13c` | 0.000026 | rejected silence |
| Baseline + FP16 only | different | 0.000027 | rejected silence |
| Baseline + DOTPROD only | `1c7090618c51ce37` | 3341.62 | 1.68 s audio |
| Baseline + corrected NEON helper | `1c7090618c51ce37` | 3341.62 | 1.68 s audio |

Feeding the good token fixture to the original baseline decoder also produced
normal audio, independently isolating the failure to token generation rather
than decoder gain or silence thresholds. No gain workaround was applied.
`bash scripts/android/test-omnivoice-dot.sh` checks 10,032 asymmetric, extreme and
random vectors against an independent scalar reference for every lane; the old
helper fails 40,024 lane comparisons. The corrected Android library compiles.
The corrected library passed `MediaPipelineTest#omniVoice` on the actual
Pixel 9 Pro in build14: 24 kHz, 40,320 samples, energy 1874.1661436266738,
87.559 seconds of synthesis/load work, `OK (1 test)`. Exact original Q8 files
were used. Device evidence: `.build/android-parity-device/omni-build14.log`.
The catalog backend can now be enabled with the experimental/slow caveat.
Local numerical controls are under `.build/android-media/omni-*.log`.
Detailed intermediate diagnostics are retained in this debug checkpoint;
no global gain boost or silence-threshold relaxation was applied.


## Android0.3.2 explicit-language OCR and speech

The user requested removing language auto-detection from both camera and speech.
`currentSource` resolves legacy/text `auto` to the last explicit language, shown
in the language selector; the Auto row is only available in text mode. Microphone
snapshots, final microphone recognition and audio imports all use that explicit
language. Automatic backend selection is retained and does not run detection.

ML Kit Text Recognition v2 16.0.1 is bundled for five scripts, selected by
`OcrRouting`. `MlKitOcr` retains only the current script client, with task-lifetime
bitmap ownership and retired-client reference counting for cancellation/switches.
No script guessing or multi-pass OCR occurs in the product. Shared OcrLayout
normalizes grouping/overlay behavior. Russian prefers validated installed
`ppocr-v5-mobile-det`, falling back to existing installed server detector only if
the mobile package is absent. The recognition weights/dictionary stay unchanged.
See OCR-OPTIONS.md and benchmarks/2026-10-12-hybrid-ocr/ for sources and evidence.
