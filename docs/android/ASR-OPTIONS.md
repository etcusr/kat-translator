## Current Android0.3.6: automatic GigaAM / Parakeet routing

GigaAM handles Russian; Parakeet TDT v3 handles its other24published languages. Both are now integrated and installed on Pixel. Missing required packages show an explicit download action rather than a silent backend substitution. Manual provider choices and fallback for other languages remain. See [routing and device tests](benchmarks/2026-10-12-asr-routing/README.md).

## Update: measured replacement on Pixel, 2026-10-12

The long-recording Pixel service probe now demonstrates silent first-phrase truncation with fast supplied PCM. GigaAM v3 INT8 was measured and integrated for Russian; Parakeet TDT v3 was measured as a multilingual alternative. See [completeness report](benchmarks/2026-10-12-asr-completeness/README.md) for timings, limitations and pinned sources. Recommendations below describe the earlier investigation, before these results.

# Practical offline ASR options for Android

Reviewed 2026-10-12 against official upstream sources and the checked-in Android runtime pins. Research only: no application changes, weight downloads, or device benchmarks were performed for this document. The user permits changing ASR models; the Index translation weight/quantization constraint does not constrain ASR.

## Recommendation and limits

First probe **Pixel's existing on-device SpeechRecognizer** for installed Russian and English support, per the user's follow-up request. A successful platform probe may avoid installing another app-owned recognizer. Do not infer API availability from Gboard or the Pixel Recorder app working. For a portable open-model fallback, benchmark **multilingual Whisper tiny and base** through the existing Whisper backend. This is the smallest integration change and provides both Russian and English in one package. In parallel, prototype **T-one for Russian plus streaming Zipformer 20M for English** using the existing sherpa C API: true incremental decoding can produce text while recording instead of deferring all work until Stop. These are two language-specific models, not one bilingual recognizer. Use explicit source-language routing initially; never label language from whichever monolingual model happened to produce output.

Neither smaller file size nor upstream desktop/server speed proves acceptable Pixel latency. The current reported multi-minute wait can include model loading, language detection, decoding, translation, queue contention, and cancellation problems. Measure those stages independently before choosing a replacement. Retain large-v3-turbo as an optional quality comparison, not a prerequisite for showing a successful short-utterance result.

## Candidate comparison

Sizes below are exact uncompressed inference-file bytes from official Hugging Face metadata fetched on the review date. They are not RAM estimates or archive download sizes. Smaller packages require their own complete size/SHA manifests before release.

| Candidate | Language and mode | Inference files / deployed total | Runtime and license | Practical assessment |
|---|---|---|---|---|
| Whisper tiny multilingual | RU, EN and other Whisper languages; utterance decoding | `ggml-tiny.bin`: **77,691,713 B** | Existing whisper.cpp v1.9.4 CPU; MIT | First latency baseline; accuracy must be checked on real Russian speech. |
| Whisper base multilingual | Same language family; utterance decoding | `ggml-base.bin`: **147,951,465 B** | Same backend; MIT | Compare quality/latency with tiny; no new ASR native engine. |
| T-one | Russian, streaming CTC, 8 kHz telephony model | `model.onnx` 144,193,702 B + `tokens.txt` 202 B = **144,193,904 B**; retain LICENSE separately | Existing sherpa online CTC API; Apache-2.0 | Russian streaming candidate. Telephony specialization and downsampling may affect wideband microphone accuracy. |
| Zipformer EN 20M | English, streaming transducer | INT8 encoder 42,845,182 B + FP32 decoder 2,092,272 B + INT8 joiner 259,572 B + tokens 5,048 B = **45,202,074 B** | Existing sherpa online transducer API; Apache-2.0 | Small English companion to T-one. No Russian support. |
| Small Zipformer RU 2024-09-18 | Russian, offline transducer | INT8 encoder 25,090,964 B + FP32 decoder 2,093,080 B + INT8 joiner 259,572 B + tokens 6,388 B = **27,450,004 B** | Existing sherpa offline transducer API; Apache-2.0 | Small Russian fallback if T-one quality or latency disappoints. VAD segmentation is simulated streaming, not a streaming acoustic model. |

Whisper files/license come from the [maintainer model repository](https://huggingface.co/ggerganov/whisper.cpp/tree/main); upstream distinguishes multilingual models from English-only `.en` files and supports [Android/CPU inference](https://github.com/ggml-org/whisper.cpp). Do not choose `tiny.en` or `base.en` for Russian. Optional Q8 files exist: tiny **43,537,433 B**, base **81,768,585 B**. Benchmark ordinary tiny/base first to distinguish model-size changes from quantization changes.

T-one's author describes a Russian-only streaming alphabet and Apache-2.0 code/models, with 300 ms processing chunks in the original pipeline. GPU throughput numbers are not phone results. [Author repository](https://github.com/voicekit-team/T-one), [original model card](https://huggingface.co/t-tech/T-one). The converted model and its expected 8 kHz input are documented by [sherpa](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-ctc/t-one-ctc-models.html).

English model provenance/license: [maintainer card](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17). Use the published combination of INT8 encoder/joiner and FP32 decoder, rather than changing every file to INT8 without testing. [Official recipe](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html).

Russian small-model provenance/license: [Alpha Cephei model card](https://huggingface.co/alphacep/vosk-model-small-ru). The [sherpa offline recipe](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/zipformer-transducer-models.html) uses encoder/decoder/joiner plus tokens; `bpe.model` is not passed for basic greedy decoding. The [official export workflow](https://github.com/k2-fsa/sherpa-onnx/blob/master/.github/workflows/export-russian-onnx-models.yaml) documents the upstream file mapping.

## Concrete downloads and immutable file identities

Whisper revision `5359861c739e955e79d9a303bcbc70fb988958b1` is already used by this project's large-v3-turbo catalog:

- [Multilingual tiny](https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny.bin): SHA-256 `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`.
- [Multilingual base](https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin): SHA-256 `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`.
- [Tiny Q8](https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny-q8_0.bin): SHA-256 `c2085835d3f50733e2ff6e4b41ae8a2b8d8110461e18821b09a15c40c42d1cca`.
- [Base Q8](https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base-q8_0.bin): SHA-256 `c577b9a86e7e048a0b7eada054f4dd79a56bbfa911fbdacf900ac5b567cbb7d9`.

Streaming Russian:

- [Official T-one archive](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-t-one-russian-2025-09-08.tar.bz2).
- Pinned converted repository revision `9d63341e0f2d8a8b2edaa825aa1fcfe3c5283b47`: [model.onnx](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-t-one-russian-2025-09-08/resolve/9d63341e0f2d8a8b2edaa825aa1fcfe3c5283b47/model.onnx), [tokens.txt](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-t-one-russian-2025-09-08/resolve/9d63341e0f2d8a8b2edaa825aa1fcfe3c5283b47/tokens.txt), [LICENSE](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-t-one-russian-2025-09-08/resolve/9d63341e0f2d8a8b2edaa825aa1fcfe3c5283b47/LICENSE). Model SHA-256 `5ded080e2a6c86ecc11bcb0902d77524eb3e8b0844cb0c0754347f5aafb4dabc`.

Streaming English:

- [Official Zipformer archive](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17.tar.bz2).
- [Pinned file tree](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17/tree/d42f2d9f7ca24806fb667456a18a9f1b60f70d16): `encoder-epoch-99-avg-1.int8.onnx`, `decoder-epoch-99-avg-1.onnx`, `joiner-epoch-99-avg-1.int8.onnx`, `tokens.txt`. Corresponding model SHA-256 values: `3810755ce7c3ab26b42a8bcf39d191308fa27fb0f53358823ba46141d03b7eb3`, `45a7f940ecfb53d89fa270ad11b88b961e53a317203eb24b1c8e95ed208b0f30`, `e085d73b593cf9b0707f370dbd656d58327d3fe36d80d849202ef81df02cb01e`.

Small Russian offline:

- [Official archive](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-small-zipformer-ru-2024-09-18.tar.bz2).
- [Pinned upstream tree](https://huggingface.co/alphacep/vosk-model-small-ru/tree/4d68c4017bcfa44e2a79581f7933339e916a35da): `am/encoder.int8.onnx`, `am/decoder.onnx`, `am/joiner.int8.onnx`, `lang/tokens.txt`. Model SHA-256 values: `75653125bf3621d86a2b140ffd84a1c3b7610fc8cd49f2b6d70cf5786be0d085`, `8537bd782f59c94b509ea501976942563e61d437373917a7736252b869e3bb2d`, `a93e0afc2c82e94d366157b4a8b5f4cba6973ddea8f36ac94010b430be7823f1`.

Hashes above are repository LFS metadata, not locally downloaded-file verification. Tokens/license hashes and archive byte counts/SHA still need to be captured before package integration. Prefer the pinned inference-only files to archives containing both precisions and sample audio. Store them once through the existing shared package repository.

## Compatibility with this app

Local `Dependencies/android-media.lock.json` pins sherpa **1.13.8**, source `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf`. The downloaded pinned C header contains `SherpaOnnxOnlineToneCtcModelConfig`, `OnlineModelConfig.t_one_ctc`, online transducer configuration, and the create/accept/decode/result/finalize stream APIs. The ARM64 library exports the needed online recognizer functions. This establishes API availability, not successful model execution on Pixel.

Use the [v1.13.8 T-one C example](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/c-api-examples/streaming-t-one-ctc-c-api.c): zero-init config, `t_one_ctc.model`, tokens, CPU provider, greedy search, initially one thread. English sets `transducer.encoder/decoder/joiner`; [official C example](https://github.com/k2-fsa/sherpa-onnx/blob/master/c-api-examples/streaming-zipformer-c-api.c). Input is normalized mono float PCM; the pinned header documents internal resampling when input and feature rates differ. Test the existing 16 kHz microphone path against T-one's 8 kHz model rather than adding an unverified resampler.

The application currently calls batch Whisper/Omnilingual adapters. Streaming requires a new persistent recognizer/stream lifecycle: accept bounded chunks, decode only when ready, publish partial text, finalize after Stop, and discard stale callbacks after cancel. Recreating models every chunk defeats streaming. Neither Python nor a new neural runtime is required. The small Russian offline model instead uses `OfflineModelConfig.transducer` with bounded VAD segments.

## Android's built-in on-device recognizer

Android offers `isOnDeviceRecognitionAvailable` and `createOnDeviceSpeechRecognizer` from API 31. It is worth a separate optional Pixel probe, but service presence does not establish installed Russian support or uniform behavior across devices. Use the explicit on-device constructor and main-thread lifecycle; do not silently substitute the generic service. [Android SpeechRecognizer reference](https://developer.android.com/reference/android/speech/SpeechRecognizer?authuser=1).

On API 33+, query recognition support and inspect `getInstalledOnDeviceLanguages`, not just online languages. Model downloads belong to the system service and cannot use this app's shared weight manifest. [RecognitionSupport reference](https://developer.android.com/reference/android/speech/RecognitionSupport). `EXTRA_PREFER_OFFLINE` alone is insufficient: the implementation may ignore it. Automatic language detection/switching and supplied-audio support also depend on the service. [RecognizerIntent reference](https://developer.android.com/reference/android/speech/RecognizerIntent). Test RU/EN with networking disabled, missing-language errors, cancel/restart, and microphone ownership. Treat system recognition as an optional platform facility, not a redistributable open-model replacement.

### Direct platform probe, before adding models

1. Check `isOnDeviceRecognitionAvailable(context)`; construct using `createOnDeviceSpeechRecognizer`, attach listener, and later `destroy`, on the main thread.
2. On API 33+, call `checkRecognitionSupport(intent, context.mainExecutor, callback)` separately for `ru-RU` and `en-US`, using the actual recognition intent. Record installed/supported/pending on-device language lists and errors. Unsupported capability queries are inconclusive, not success.
3. If a required language is downloadable, expose a separate system download action via `triggerModelDownload`; recheck readiness afterwards. This is not evidence of a locally installed language until completion. [Platform API contract](https://developer.android.com/reference/android/speech/SpeechRecognizer?authuser=22).
4. Probe supplied audio separately. API 33 `EXTRA_AUDIO_SOURCE` takes a `ParcelFileDescriptor`; specify mono, PCM16, and sample rate. Close the descriptor on completion/cancel. If unsupported, the service may open the microphone instead, so a supplied-audio test must prove the output corresponds to the fixture while the room is quiet. Check the same intent and observe runtime behavior; a support callback alone is not a substitute for that test. [Supplied audio contract](https://developer.android.com/reference/android/speech/RecognizerIntent#EXTRA_AUDIO_SOURCE).
5. Then test real microphone input, offline, in both languages; record first partial/final latency and cancel/restart. No network-service fallback should be enabled. Preserve the app's current microphone/preview state during the probe.

### ML Kit speech / AICore alternative — current documented limits

Google's speech guide (updated 2026-10-08) documents `com.google.mlkit:genai-speech-recognition:1.0.0-alpha1`. Basic mode supports API31+ devices, English and Russian (Russian is beta). Advanced Gemini speech lists Pixel10/11 only: **Pixel9Pro is not listed for Advanced speech**, regardless of its support for other AICore features.

Use a Basic-mode client and `checkStatus()` before offering it: distinguish AVAILABLE, DOWNLOADABLE, DOWNLOADING and UNAVAILABLE. Downloads are managed by the service. Microphone and descriptor input are supported; descriptor input must be raw headerless PCM16 mono16kHz, fed at real-time speed. Full-speed file-backed descriptors are currently unsupported. This differs from immediately decoding an entire saved clip through Whisper. The API is alpha, and the guide says unlocked bootloaders are unsupported. These are documented capabilities, not a result from this Pixel. [ML Kit Speech Recognition guide](https://developers.google.com/ml-kit/genai/speech-recognition/android).

AICore shares system-managed models and runs inference locally. Initial configuration/model preparation can still require a network connection. Do not confuse general Pixel9 Gemini Nano support with the speech-specific device list. [ML Kit GenAI overview](https://developers.google.com/ml-kit/genai).

## Pixel comparison plan — proposed acceptance criteria, not measured results

1. Use the same saved 5–10 second RU and EN human recordings for every model: ordinary phrases, names, negation, numbers/time, noise, and silence. Include live microphone tests afterwards; synthesized speech alone is insufficient.
2. Time cold load, warm decode, time to first partial, finalization after Stop, and total tap-to-visible-text separately. First run ASR without translation/TTS; then test the full product path.
3. Compare tiny/base, T-one RU + Zipformer EN, and small Russian offline with 1/2/4 CPU threads. Keep power/thermal conditions recorded and avoid concurrent inference. Current user instruction disables thermal waits for these functional checks. Keep only the selected model warm.
4. Initial usability targets: warm processing faster than audio duration; final text within 2 seconds after Stop for streaming; cancel acknowledged promptly and a new request usable within 2 seconds. Record actual percentiles and failures, not just one best run. A target failure is evidence to reject/tune that candidate, not permission to hide the delay.
5. Report WER/CER plus critical mistakes (names, dates, numbers, polarity), peak RAM, model load time, battery/thermal behavior, silence hallucinations, and 20 consecutive cancel/restart cycles. Check partial text cannot overwrite a later session.
6. Promote a default only after RU and EN each produce visible useful results on the user's Pixel. Preserve a quality alternative and explicit language selection. Do not alter Index translation weights or quantization as part of ASR evaluation.
