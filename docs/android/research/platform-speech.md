# Android on-device recorded-audio recognition

Update for Android0.3.2: user requested removal of speech language detection.
The product now always passes an explicit source language for microphone and
imported audio; old saved `auto` uses the last manual language shown in the UI.
The adapter auto branch and the two-pass results below are historical research
capabilities, not an available product mode. Backend selection `automatic` still
selects the system adapter without language detection.

`SystemSpeechRecognizer` is now the automatic Android path when an on-device
service is available and no separate recognition model is selected. It constructs only `SpeechRecognizer.createOnDeviceSpeechRecognizer`;
there is no generic service, network fallback or model download request.

The worker API is `SystemSpeechRecognizer(context).use { it.transcribe(samples,
source, isCancelled) }`, returning the existing `Transcript`. Samples are mono
Float PCM at 16 kHz. `source` accepts `en`, `ru`, explicit BCP47 tags or `auto`.
`cancel()` is reusable; `close()` permanently closes the adapter. All service
creation, support checks, listening, cancellation and destruction run on main.
Call from a worker while the app is foreground and RECORD_AUDIO is granted.

Android 13+ injected input supplies PCM16 through EXTRA_AUDIO_SOURCE. The exact
same intent is checked and then started; required languages must appear in
installedOnDeviceLanguages. EXTRA_SEGMENTED_SESSION uses EXTRA_AUDIO_SOURCE so
EOF terminates the session. Final segment text is concatenated. Partial results
are not accepted. A private temporary raw PCM file is deleted at completion.
FILE is the default. Explicit InputMode.PACED_PIPE writes 20 ms chunks in real time
if separately selected for a service which cannot process fast file input; no
automatic transport fallback occurs.

Android 14+ auto requests language detection and balanced switching, limited to
installed en-US and ru-RU. It returns the actual confident language callback,
never the initial en-US hint. It then replays the complete identical recording
with that explicit language: Pixel switching otherwise dropped the Russian
greeting. Both passes share cancellation and one deadline. Missing confident
language fails clearly. Mixed
language input currently reports the last confident detected language; the
existing Transcript represents one language only.

`PlatformSpeechAudioTest` runs in MainActivity to provide foreground service
access, with existing UiTestEnvironment restoring preferences afterwards. Audio
fixtures are SHA-verified synthetic EN Piper / RU Supertonic files. No user audio
is loaded. Select methods separately:

1. `fileEnglish` and `fileRussian`: fast file input, actual critical words,
   language and elapsed/real-time-factor metrics.
2. `fileAutoEnglish` and `fileAutoRussian`: same recordings plus actual detected
   language, no requested-language substitution.
3. `cancellationThenReuse`: cancel a supplied silence session after 250 ms,
   require return within 3 seconds, then transcribe real EN on the same adapter.
4. Only if file input fails: `pacedEnglish` and `pacedRussian` explicitly exercise
   the pipe transport. They do not change the default.

Each normal operation has a 45-second deadline; each test a 65-second outer bound.
Reports start with PLATFORM_SPEECH and include actual transcript/error and timing.
Pixel 9 Pro acceptance (2026-10-12): explicit EN 1.320 s / RU 2.383 s,
cancel 252 ms and successful reuse. Auto with complete-audio replay EN 2.790 s /
RU 7.641 s, no lost greeting. Product import → system ASR → OPUS → visible text
passed: explicit RU 3.421 s, auto RU 8.522 s on a 6.520 s synthetic recording.
These are individual functional samples including service setup, not latency
percentiles or human-speech WER. Logs: platform-audio-build19.log and
system-flow-build20.log under.build/android-parity-device. The service reports
installed ru-RU/en-US. Only the explicit on-device constructor is used; device
radios were not disabled for these tests. Paced transport is not device-accepted.

Official contracts:
- https://developer.android.com/reference/android/speech/RecognizerIntent#EXTRA_AUDIO_SOURCE
- https://developer.android.com/reference/android/speech/RecognizerIntent#EXTRA_SEGMENTED_SESSION
- https://developer.android.com/reference/android/speech/RecognitionListener#onLanguageDetection(android.os.Bundle)
