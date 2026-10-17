# Android streamed Piper and retained model contexts — 17 October 2026

The development app now plays Piper PCM as it is generated, retains the selected Whisper and Piper contexts when memory permits, and can load the voice while translation runs. Model weights, four-thread inference, Whisper decoding and Piper generation settings are unchanged. Translation still finishes before synthesized speech starts; this is not partial-translation speech.

## Measured time on the same recording

| Build/run | First playback, s | ASR, s | Translation, s | Full synthesis, s | Processing finished, s |
|---|---:|---:|---:|---:|---:|
| Before, cold | 25.61 | 13.41 | 2.97 | 8.43 | 25.61 |
| Before, repeat | 25.28 | 13.67 | 3.06 | 8.27 | 25.28 |
| First streaming candidate, cold | 20.02 | 13.31 | 3.24 | 7.28 | 24.69 |
| First streaming candidate, repeat | 18.10 | 12.30 | 3.04 | 7.14 | 22.70 |
| Final installed build, cold | 20.34 | 13.53 | 3.49 | 7.35 | 25.04 |
| Final installed build, repeat | 17.95 | 12.15 | 3.07 | 7.03 | 22.51 |

As an approximate separation of speech waiting from ASR/translation, subtracting their measured durations from first playback gives 9.24/8.56 s before, and 3.32/2.72 s in the final build. This residual also includes import/scheduling overhead; it is not a direct translation-end-to-audio timestamp. Complete synthesis duration remains separately reported.

Cold means a fresh application process; repeat keeps the selected native contexts in that process. Both final runs follow at least six minutes of cooling, without backgrounding between them. Baseline and first-candidate observations are also included. Their thermal checks were only before/after; the final comparison samples throughout. An intermediate attempt on the final build measured 26.19/23.79 seconds and developed CPU frequency restrictions; it is retained in the JSON but excluded from the speed comparison.

On the final repeat, first playback changed from 25.28 to 17.95 seconds (29.0% less waiting). Each model was loaded once across both final imports. Final raw transcription and translation exactly match both baseline runs and both first-candidate runs.

Final preflight required at least six minutes and two readings ten seconds apart with skin ≤34°C, battery ≤35°C, GPU ≤45°C and no CPU/GPU/uclamp restriction. Screen stayed awake during the final comparison. The final 13 sampled readings contained 3 temperature-warning samples (G3D ≥65°C), but zero reported CPU/GPU/uclamp frequency restrictions and zero non-NONE Android thermal statuses. Temperature details and all numeric results are in [measurements.json](measurements.json).

Installed artifact: development version **0.4.6 (21)**, APK SHA-256 `bfedee1957c059f72e86f0f6c6ec97a0beadda1bebf0cc3004678ad5e6ba76c3`. Existing distribution APKs were not rebuilt by this task.

## Ownership and playback

- Each utterance owns one queue and one `AudioTrack`. Closing input drains it; stopping discards queued PCM and rejects late producers. A playback epoch prevents delayed main-thread posts from restarting stopped audio.
- Native Piper copies each callback before its native storage is freed. It verifies that the ordered callback aggregate equals the final native output from that same invocation. The final aggregate is never enqueued again. This matches the pinned VITS implementation, which appends the exact callback arrays to its result.
- The player starts with at least four seconds of generated PCM, or all of a completed shorter utterance. This fixed initial reserve corrected an observed underrun after a very short opening sentence. Synthesis continues independently while the queue plays.
- Loudness uses the existing bounded gain and soft limiter. At least 0.8 seconds of initial PCM, or the complete shorter utterance, determines one fixed gain. Replay and export use exactly the normalized fragments queued for playback. This changes the gain-estimation window from the previous whole-utterance normalization; it does not change the voice model.
- Original-recording replay estimates loudness on the playback worker and adjusts 2,048-sample windows; it neither changes the ASR source samples nor creates a second full recording array. Export keeps the same recording gain.
- Pause, speed changes and release serialize on the playback session. The AudioTrack buffer has headroom for 2× playback; a 128-frame utterance also drains successfully.

## Model lifetime

`OfflineMedia` owns one Whisper handle and one Piper handle. Canonical file paths, sizes and modification times identify the loaded model. Replacement frees the previous handle before loading the next; failed loads are not cached. Baseline and optimized Whisper handles are created, run and freed by their own libraries.

The app retains models only with at least 11.5 GB total RAM, at least max(2 GB, twice the Android low-memory threshold) available, and no memory-saving/low-memory signal. Checks run after recognition, before translation, after work, and every 15 seconds while idle in the foreground. Backgrounding, explicit unload, package operations, model changes and close also release the appropriate cache. Small-memory devices retain the prior per-operation lifetime. One voice slot means a language/voice change may reload Piper; a two-voice LRU is not implemented. Cancelling during the non-interruptible voice load can wait for that load to finish; stopping playback immediately invalidates its queue.

Android 14+ no longer sends the old running-low-memory and `onLowMemory` callbacks, so the implementation does not rely solely on them. [Android ComponentCallbacks2](https://developer.android.com/reference/android/content/ComponentCallbacks2).

## Functional evidence

The real imported-audio path checks native callback equality, successful AudioTrack drain, written frame count equal to played frame count and exported WAV frame count, and zero underruns before the final drain. A separate final empty-buffer notification after all frames were written is recorded separately; it is not an inter-fragment gap.

Device scenarios cover stopping during synthesis, rejecting late restart, replaying the complete saved utterance without synthesis, unloading/reloading the voice, cancelling an active Whisper encoder then reusing its context with identical output, and releasing/reloading recognition on a memory-trim request. Additional fixtures cover a short opening, multiple punctuation marks, a newline, numbers and a one-word utterance. Callback/queue tests also check order and one-time final flush.

Contextual Russian ordinal expansion is now connected before Piper/MMS/Supertonic; its ported unit fixtures pass. Recording preprocessing defaults on only when no saved choice exists. It remains gated to Index + Whisper and does not affect this OPUS imported-audio comparison.

### Reproducing the device check

Build/install the debug app and app instrumentation APK. Place a local 16 kHz mono WAV in the app's private cache as `asr-latency-input.wav`; the selected Q8 recognizer, RU→EN OPUS package and English LJSpeech-high voice must already be installed. Run `StreamingLatencyTest` with instrumentation arguments `streamingLatency=true`, `streamingRepeats=2`, and `streamingGate=true`. After the first import, `cache/streaming-ready` signals the host to wait for the cooling interval and readings above, then create `cache/streaming-continue`. Keep the app foregrounded and the screen awake; do not force-stop between imports. The test exports private JSON, transcript, translation and WAV evidence to cache and restores saved preferences afterward. The default ungated 45-second pause is not sufficient for a thermally controlled comparison on this device.

### Checks and test coverage

- 118 JVM tests passed (68 app, 50 inference); 143 Python validation tests passed; Android lint and debug builds passed.
- Pixel passed seven native boundary tests, five player lifecycle/drain tests, three streaming-control scenarios, two original-recording/export actions, and the full two-import comparison. Russian ordinal fixtures cover 28 conversions and 17 unchanged inputs.
- An existing standalone voice-download notice test failed because its fixture expected Russian outside the language provider (default English). Supplying the Russian provider fixed the fixture; the isolated test passed. Product localization was unchanged.
- The installed APK SHA-256 matches the built APK; application preferences match the pre-test snapshot. No user history was inspected or cleared.

## Scope and limits

The private fixture is 28.859875 seconds, mono PCM16 at 16 kHz. The same Q8 recognizer, RU→EN OPUS route, English LJSpeech high voice and 1.25× playback are used before and after. Private audio, translations, transcripts and device identifiers are excluded from this report and Git.

Timing starts at file import and measures application playback start, not a microphone measurement of acoustic onset. AudioTrack frame accounting and independent recognition of exported speech are not a physical speaker capture or a broad multilingual listening study. Independent speech recognition retained the sentence sequence, ending, date and time, with minor variation around the technical model name. Piper is stochastic, so PCM/duration can vary across separate invocations; equality is checked within each invocation instead.

No VAD trimming or MTP change is shipped here. A conservative −45 dB / 0.2-second silence check found no removable silence interval in this recording. MTP applies to Index rather than the selected OPUS route. A comparison that ended in thermal throttling and another cold run started behind the lock screen are excluded from the speed comparison. The final comparison starts with the screen awake and keyguard dismissed; settings that keep the screen awake are preserved. Bluetooth route changes, incoming-call interruptions and arbitrary long/multilingual texts need their own acceptance tests.
