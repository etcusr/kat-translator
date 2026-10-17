# Further Pixel latency investigation — 17 October 2026

The second private recording is 28.859875 seconds, mono PCM16 at 16 kHz. The existing Pixel 9 Pro development app **0.4.6 (21)** remains installed and unchanged. Recognition uses large-v3-turbo Q8 and speech uses Piper LJSpeech High. This is a diagnosis and a measured implementation proposal, not a new accelerated APK.

## Fresh measurements

Two opt-in application tests passed, with history/audio saving disabled and preferences restored. Recognition: **13.253 s**, OPUS translation: **3.096 s**, total before speech: **16.960 s**. A separate speech test on the same 215-character translation took **8.876 s**: voice loading **1.175 s**, synthesis **7.407 s**, copying **0.0007 s**, release **0.041 s**, other work **0.253 s**. These separate runs are not a new single end-to-end first-audio measurement.

Seven native Whisper runs and four native Piper runs are recorded in [measurements.json](measurements.json). Inputs/transcripts/audio, signing data and device identifiers are excluded from this report.

| Whisper Q8 configuration | Inference, excluding load | Encoder | Decoder |
|---|---:|---:|---:|
| Four threads, baseline | 12.665 s | 10.662 s | 1.780 s |
| Four threads, CPUs 4–7 | 12.327 s | 10.664 s | 1.469 s |
| Three threads, CPUs 4–7 | 16.477 s | 13.713 s | 2.524 s |
| Four threads, control | 12.615 s | 10.801 s | 1.584 s |
| Six threads | 18.181 s | 13.053 s | 4.842 s |
| Eight threads | 27.705 s | 12.647 s | 14.551 s |
| Four threads, final control after cooling | 12.285 s | 10.518 s | 1.531 s |

All seven transcripts exactly match the application transcript, without supplying a prompt. That is agreement on one recording, not a human reference or broad accuracy evaluation. Four-thread affinity is within the spread of ordinary four-thread controls; it is not a demonstrated improvement. Six threads regressed without detected thermal restrictions. Eight threads started without compute restrictions but ended with CPU throttling, so its magnitude is confounded by heat. Every run began at thermal status NONE with skin at most 35.5°C and no CPU/GPU/uclamp restrictions; starting temperatures were not identical. Model load takes about 0.93–0.99 s. The encoder dominates; this does not prove that the CPU implementation has reached its ultimate limit.

Piper's four-thread synthesis took 7.073 s initially, 6.863 s pinned to CPUs 4–7, and 6.901 s in the unpinned callback control. Three pinned threads took 9.031 s. No reliable affinity improvement was demonstrated. Piper is stochastic with the existing noise settings: different runs need not have identical durations or PCM.

## Confirmed first-audio opportunity

The production Sherpa call already produces sentence callbacks, but `SpeechRuntime.c` discards their samples and only checks cancellation. Android's `TranslatorState.synthesizeImpl` collects all audio, normalizes the complete result, and only then calls the player.

In a native observer with unchanged model, text, noise, speed and thread settings:

- Voice load: **1.282 s**.
- First fragment: **2.477 s after load**, or **3.759 s from synthesis setup**.
- All fragments: **6.901 s after load**, or **8.182 s including load**.
- Four callbacks contained **339,456 samples at 22,050 Hz**. Their concatenation was **bit-for-bit equal** to the returned final PCM, in the same synthesis invocation. No text segmentation or second synthesis was introduced.
- Callback readiness and fragment lengths predict no queue underrun at 1×, 1.25× or 2× in this trace. This is a timeline calculation, not an AudioTrack streaming acceptance test.

Thus **4.42 s of waiting can potentially be removed before first audio in this native run** by consuming already generated samples. Total synthesis computation is unchanged. App integration, audio-focus overhead, loudness handling, cancellation and real playback still need implementation and measurement; do not advertise 3.76 s as an installed-app result.

## Implementation priority

1. **Consume native Piper callbacks in one cancellable playback session.** Queue every callback once; never play the final aggregate again. Keep the complete aggregate for replay/export. Stop must invalidate queued callbacks and pending main-thread work. Preserve pause, speed, audio focus and natural completion. Decide and validate streaming loudness normalization: current full-utterance gain depends on audio that has not been generated yet, so raw PCM equality alone does not establish identical normalized output.
2. **Retain loaded voice and Whisper contexts when memory permits.** The measured load costs are roughly 1.2 s and 0.9 s. Explicit unload, model replacement, memory-saving mode and cancellation need safe ownership. These are potential repeat-turn savings, not implemented or measured cached-engine gains.
3. **Benchmark the same Whisper checkpoint with another CPU execution backend, beginning with CTranslate2/Ruy.** Its official documentation supports [Whisper](https://opennmt.net/CTranslate2/python/ctranslate2.models.Whisper.html) and [ARM64/Ruy INT8](https://opennmt.net/CTranslate2/quantization.html). That makes it a candidate, not evidence that it is faster on Pixel. Match frontend, language, greedy decoding and generation limits; compare both private recordings plus a broader synthetic suite. A converted INT8 model is not byte-equivalent to GGML Q8, so quality needs a fresh comparison. No conversion, download or backend replacement was performed here.
4. **Evaluate recording-time preprocessing separately from file import.** The current Android option defaults off and only starts with Index + Whisper, memory saving off and acceptable thermal state; OPUS does not enter it. Imported audio cannot benefit from work done during capture. Enabling the option alone does not fix the shown OPUS/import path. Context boundaries, repeated words and complete final coverage must be tested before extending it.

The current [Google Tensor SDK supported-SoC list](https://developers.google.com/edge/litert/next/tensor-sdk) names **G5/G6**, not this Pixel 9 Pro's G4 (checked 17 October 2026). Do not plan a drop-in TPU switch for this device or generalize that no Pixel TPU API exists. The older LiteRT delegate overview is superseded by the newer Tensor SDK documentation for supported devices.

## Completion and limits

No production settings, models, code, APK or distribution artifacts were changed. All saved preferences matched after the tests. The task's temporary audio, text, probe directory and result files were removed from the phone; the normal app was reopened. Existing model payloads were not replaced. This is import/native profiling, not a fresh live-microphone, streamed-player, human listening, all-language or sustained thermal acceptance run. Prior smaller-model/context experiments remain in the [earlier comparison](../2026-10-17-whisper-options/README.md), not rerun here.
