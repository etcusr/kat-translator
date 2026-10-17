# iPhone speech correctness — 17 October 2026

The corrected Apple speech pipeline from `da97150` was built in signed Release configuration and installed over the existing Kat app on a physical iPhone 17 Pro. Development version remains **1.0 (52)** with the same bundle identity. Signature verification passed; this was a local installation, not an App Store/TestFlight upload.

## Fresh device results

| Scenario | Synthesis fragments | Completed playback buffers | Audio length | Result |
|---|---:|---:|---:|---|
| Fixed translation: long sentence, newline/tab/double spaces, Russian ordinals | 4 | 3 | 15.719 s | PASS |
| Real routed Index 9B → Irina, six sentences | 6 | 6 | 15.596 s | PASS |

Both cases used the production `ConversationPipeline`, `SherpaSpeechBackend` and **real iPhone `SpeechPlayer`**. The controlled translator isolates exact wording and whitespace; the second case uses the actual installed Index 9B model. Irina was the selected installed Russian voice. No recognizer or microphone supplied input to either case.

All translated words reached synthesis exactly once and in order. Speech began before translation finished in both cases. All nine playback calls returned through the player's `dataPlayedBack` completion path; measured wall time exceeded the corresponding PCM duration, with no premature completion or playback error. The output route was the phone speaker at nonzero volume. The probe also saved the exact generated PCM at 22,050 Hz, with finite non-silent samples.

Independent local Whisper large-v3-turbo F16 recognition of both saved waveforms, without a prompt, matched the complete expected word sequence after normalizing punctuation, case, `ё`/`е` and conventional number renderings. The controlled audio covered:

- «на первой улице» from `на 1-й улице`;
- «перед первым рейсом» from `перед 1-м рейсом`;
- «с пятнадцатого на шестнадцатое октября» from `с 15-го на 16-е октября`;
- «восьмидесятые годы» from `80-е годы`.

This confirms these regression scenarios on the phone. It is not an acoustic recording of its speaker, a subjective listening-panel assessment, or coverage of all Russian grammatical contexts. The conservative ordinal rules and already-spoken-prefix rewrite limit from the [implementation report](../apple-speech-correctness-2026-10-17/README.md) still apply. The earlier 3.1-second iPhone latency result was not remeasured here.

## Reproduction and cleanup

`RecordingPreviewProbe` now has an explicit synthetic device mode: launch with both `OT_RECORDING_PREVIEW_PROBE=1` and `OT_SPEECH_CORRECTNESS_PROBE=1`. It requires installed Index 9B and a selected Russian voice, writes only its fixed synthetic fixtures to `Documents/SpeechCorrectnessProbe`, and uses no history archive or saved-setting overrides. A bounded wait in the controlled translator fails if speech never starts. Results include ordering, synthesis inputs, playback completion/timing, output route, and PCM.

Export that directory through the development container tools. Launch with `OT_SPEECH_CORRECTNESS_PROBE=cleanup` (and the recording-probe flag) to remove only this directory. Cleanup was verified, and the installed app was then opened normally without probe flags. Saved preferences compared equal before and after the checks. History contents were outside this speech verification.

The signed build, two device cases, two independent waveform comparisons and documentation parity checks passed. Raw audio, logs, local signing/device information and private snapshots remain in ignored local build output. The public measurement file contains only synthetic-case counters and timings.
