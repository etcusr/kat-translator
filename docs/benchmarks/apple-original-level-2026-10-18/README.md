# Quiet original recordings on Apple — 18 October 2026

## Evidence and diagnosis

A privately supplied iPhone microphone export was already quiet in the M4A file; this is not solely a speaker/playback-volume issue. The owner described recording another device's speaker at close range. The private audio, screenshot and transcript are not included here.

| Decoded audio | Duration, s | RMS, dBFS | Peak, dBFS | Samples at/above full scale |
|---|---:|---:|---:|---:|
| Supplied original export | 17.408125 | -44.75 | -12.65 | 0 |
| Supplied synthesized translation | 14.260000 | -16.73 | -1.22 | 0 |
| Original re-exported by the corrected cache | 17.408125 | -16.13 | -1.26 | 0 |

Measured by decoding to mono Float32 PCM at 16 kHz with ffmpeg; RMS is over the complete file, not LUFS or a subjective listening score. The corrected copy is 28.62 dB above the supplied original and within 0.60 dB of the translation. The already-exported file is the input to this check: raw pre-export microphone samples are unavailable. This is a real cache/AAC file test on Mac, not a fresh acoustic iPhone recording.

`VoiceRecordingCache` previously reused synthesized-speech normalization: a fixed -46 dBFS activity gate and at most fourfold gain (+12 dB). This cannot adequately raise very quiet capture, and handling clicks can become the only windows above the analysis gate. A synthetic quiet waveform with a click reproduced the low exported level before the fix. Sharing copies the cached M4A; it does not reduce its gain again. Both file playback and sharing therefore use the same quiet original.

The capture session's `.measurement` mode and these old normalization limits predate the AudioQueue startup optimization. Apple documents that [measurement minimizes system signal processing](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement). This does not establish the cause of this recording's low raw microphone level, or prove/disprove a live AudioQueue amplitude regression. No matched live capture comparison was performed here.

## Accepted change

Only the saved original receives a separate normalization policy; Whisper/VAD input and synthesized speech retain their previous samples and policy. The shared Apple cache covers iOS and Mac replay, export and newly saved history. Android is unchanged.

Analyze 20 ms RMS windows, excluding values below -70 dBFS before percentiles and requiring at least five eligible windows. The 90th-percentile power must exceed -60 dBFS. Use a relative activity gate 20 dB below that reference, bounded by -70 dBFS; omit the loudest one percent of windows when estimating gain so isolated handling transients cannot dominate it. Target active RMS 0.16 (about -16 dBFS), with a maximum fixed gain of 100 (+40 dB). Apply one gain to the complete utterance, preserving pauses and relative phrase levels. Already loud input is not amplified or limited again.

A soft limiter starts at magnitude 0.55 and approaches 0.70 for amplified originals, leaving more AAC headroom than the unchanged TTS limiter. The initial candidate with the TTS ceiling produced a decoded peak of 1.0537 and ten over-range samples on the private export; a failing test caught this. The final re-export has no over-range samples. This is bounded amplification, not noise removal: audible background noise also rises, and clips below the activity floor or beyond the gain limit may remain quiet. It does not guarantee clipping-free decoding for every possible signal/codec.

## Validation and limits

- Failing AAC regression before the fix: quiet voice section RMS 0.00705, required above 0.075. Final pass preserves the 2:1 level difference between sections, duration, peak headroom and unchanged recognition samples.
- Four synthetic voice levels, handling clicks, long pauses, silence, low noise, already loud and non-finite input checked. A long-pause control caught and corrected percentile dilution before final acceptance.
- Full OfflineCore suite: 330 tests, two unrelated opt-in skips, no failures; the private recording probe ran explicitly and passed. Input file bytes remained unchanged.
- All 143 project validation checks passed, including bilingual documentation parity.
- iOS Release build succeeded with code signing disabled. No install, Store upload, DMG/ZIP refresh or version bump in this task. Existing recordings in history are not rewritten.
- The fixed export and compact local logs are retained outside Git. Public evidence contains only measurements and synthetic tests.

Reproduce synthetic checks with `swift test --package-path shared/packages/OfflineCore --filter 'VoiceRecordingCacheTests|SpeechLoudnessTests'`. The optional private probe uses `KAT_RECORDING_LEVEL_INPUT` and `KAT_RECORDING_LEVEL_OUTPUT`; leave them unset in ordinary CI. [Measurements](levels.json).
