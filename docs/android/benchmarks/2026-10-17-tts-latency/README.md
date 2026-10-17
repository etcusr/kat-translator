# Android VITS speech latency — 17 October 2026

On Pixel 9 Pro, the selected English LJ Speech high voice spent most of its latency generating audio, rather than loading weights. The product now gives Android VITS/Piper (including MMS through that runtime) up to four CPU threads, capped by the online processor count, instead of two. Apple and Supertonic thread settings are unchanged. No model, quantization, noise scale, length scale, phonemization, playback rate or loudness-normalization changes.

## Product measurement

Same installed voice `vits-piper-en_US-ljspeech-high`, same 257-character input, one complete uncached synthesis per run. Original input/audio are private and are not published. Both runs began without a thermal frequency restriction; restrictions appeared during both (stronger in the longer baseline). These are device measurements, not a promise for all Android devices.

| Phase | Before, seconds | After, seconds |
|---|---:|---:|
| Load voice | 1.294 | 1.187 |
| Generate audio | 15.770 | 8.891 |
| Validate/copy native PCM | 0.001 | 0.001 |
| Release native resources | 0.067 | 0.067 |
| Other product preparation/normalization | 0.244 | 0.273 |
| **Total synthesis stage** | **17.377** | **10.419** |

Total reduction: **40.04%** (1.67x); generation itself: 1.77x. The original screenshot's 16.48 seconds is historical, not this fresh baseline. An earlier slightly throttled app run took 18.205 seconds, of which 16.608 were generation. Native exploration found roughly 15.3 seconds at two threads, 16.4 at one and 8.9 at four. Six threads did not improve on four; later heated runs were excluded from the headline comparison. Reusing a voice engine saved its loading cost but left generation near 14.9 seconds, so caching alone would not address the main delay; voice lifecycle remains unchanged.

## Quality and functional checks

The same weights and synthesis parameters are used. Product-normalized output before/after: 22,050 Hz, 16.433/16.283 seconds, peak 0.890/0.889, RMS 0.146/0.149, zero clipped PCM16 samples. VITS noise makes separate syntheses non-identical even without a code change. Independent local Whisper decoded the same number sequence, hotel request, date and time in both; an already malformed word in the input remained ambiguous. This is a limited intelligibility check, not listening-panel or multilingual quality certification.

107 Android unit tests, lint and app/test APK builds passed. The two `VoiceResultPlaybackTest` cases passed (automatic speech, stop/replay, paused stop, natural completion and visible panels). Isolated `MediaPipelineTest#piper` and `#supertonic` each passed. The first combined invocation failed only when those standalone tests tried to open the model repository already owned by the preceding Activity tests; each passed when run separately as their documented harness requires. Two product profiling runs before optimization and one after passed. No live microphone or Bluetooth acceptance.

## Reproduction and diagnostics

`SpeechLatencyTest#profileSelectedVoice` is opt-in: put a UTF-8 input in the app cache as `tts-latency-input.txt`, then run instrumentation with `-e speechLatency true -e speechRepeats 1`. Optional `speechLanguage` and `speechVoice` select the comparison. History saving is disabled and preferences are restored by `UiTestEnvironment`. Results contain only timings/model ID/character count; private text is not logged. The final normalized WAV and JSON remain in cache for retrieval and must be removed after the check. Native phase timings are available through `OfflineMedia.lastSpeechTiming`; JNI reports load, generation, PCM validation/copy and release using a monotonic clock.

For isolated thread exploration, build `scripts/android/tts-probe/build.sh` and run the resulting ARM64 probe with model, tokens, eSpeak data, input-text file, threads and repeat count. It uses the same VITS parameters and never prints the input. An optional prefix exports WAVs. Use the actual runtime libraries and control thermal state; do not run benchmarks concurrently.

The rebuilt development APK was installed over version 0.4.6 / code 21. No version bump, model replacement, Apple build, public release or push. Remaining latency is dominated by inference; models are still loaded for each synthesis. Speed on other phones and voices needs separate measurement.
