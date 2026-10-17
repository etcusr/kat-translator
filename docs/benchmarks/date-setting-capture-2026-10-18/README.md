# Recognition preparation and optional date repair — 18 October 2026

## Accepted behavior

- iOS, macOS and Android load the selected ASR during Voice preparation before exposing the microphone. Text/Camera invalidate readiness and release ASR after active native work finishes. Returning to Voice requires preparation again.
- Rapid tab changes, cancellation and memory pressure cannot publish stale readiness. An uncancellable native load must be released when the current tab no longer needs ASR. Switching to Text while MT is still loading skips the pending ASR allocation.
- Memory-saving Voice preparation loads ASR and defers MT. Android's system recognizer exposes service availability, not control over OS model residency. Apple Camera keeps its separate translator/full-unload policy.
- `whisperDateTimeRepair` is saved and **false by default** on all three platforms. Off preserves the ordinary transcript without retry. On conditionally verifies a short ambiguous Russian time/day sequence acoustically. It may increase waiting time; unrelated numbers are not rewritten.
- Recording preprocessing remains enabled by default and existing saved choices are preserved.

## iPhone microphone startup

Startup traces distinguish ASR preparation, audio session setup, `AVAudioEngine.start()` and the first received PCM callback. The initial ASR load was 0.805 s; repeated preparation checks were 0.030–0.032 s. The recurring delay was inside `AVAudioEngine.start()` (approximately 1.18–1.21 s).

The engine now starts outside the UI thread. Its local ownership prevents a concurrent stop while native startup is in progress; cancellation pauses the sink immediately and disposes of a late engine before publishing recording state. Three traces show a main-thread response at 0.117/0.109/0.109 s after the tap, while engine startup finishes at 1.305/1.286/1.281 s. First PCM callbacks arrive at 1.398/1.376/1.375 s. Callback time includes audio batching and is not the exact first physical sample time.

This removes the UI freeze and moves recognizer loading before the microphone. It **does not eliminate the approximately 1.2-second native audio startup delay**. Ordinary launches do not enable tracing. No background microphone is kept running between recordings.

## Real recognition checks on Mac

The current Whisper backend and unchanged F16 model processed one private recording and eight synthetic numeric controls, each with the setting absent, enabled and explicitly disabled (27 recognitions). Absent and disabled outputs matched exactly in all nine cases. Enabled corrected three ambiguous time/day cases; six other cases remained unchanged (date-first, explicit time, money, count, decimal and phone number).

| Case | Default, s | Enabled, s | Disabled, s |
|---|---:|---:|---:|
| Private recording | 0.841 | 2.740 | 0.784 |
| Synthetic train | 0.780 | 2.314 | 0.757 |
| Synthetic meeting | 0.772 | 2.279 | 0.766 |
| Date first | 0.747 | 0.786 | 0.807 |
| Explicit time | 0.744 | 0.766 | 0.781 |
| Money | 0.765 | 0.784 | 0.798 |
| Count | 0.817 | 0.822 | 0.831 |
| Decimal | 0.820 | 0.795 | 0.808 |
| Phone number | 0.762 | 0.765 | 0.786 |

These sequential observations describe this fixture set; they are not a randomized performance benchmark or general accuracy estimate. Private audio and transcripts are excluded from the repository.

## Android device checks

Native date-repair checks passed through baseline, ARM82 and i8mm owners: the synthetic ambiguous train case was corrected twice, disabled mode retained the exact ordinary result, money was unchanged, pre-cancel reached both entry points, and cached handles were reusable. Total test times were 437.397/160.416/133.056 s respectively; these include multiple sequential recognitions and are not per-recording performance comparisons.

On Pixel, the four final Voice lifecycle tests passed: Whisper Q8 preload before microphone, Text/Camera release with OPUS retained, Voice return, memory pressure, rapid switching/cancel/reprepare, missing recognizer and ASR-only memory-saving preparation. A queued Voice return followed by cancel, pressure or backgrounding does not reload models; the original failure was reproduced before the fix. Actual GigaAM, Parakeet and Omnilingual preload/reuse/free checks passed using existing installed packages. First loads were 1.532/3.183/1.705 s; repeated preparation did not increment load counters. Family replacement, cancelled preparation followed by reuse and repeated release passed. No inference or recording was part of those residency checks.

## Fresh Apple device and build checks

- OfflineCore: 311 tests, 2 opt-in skips, no failures. New tests cover tab transitions during ASR and MT loading, cancellation cleanup, pressure and memory-saving preparation.
- Mac Release runtime suite: 63 tests, 16 opt-in skips, no failures. This includes external text arrival during ASR preparation. An earlier run exposed that integration regression; it was fixed and covered by a new suspended-load test. One resource-sampling assertion failed in that earlier run and passed on the final rerun; its implementation was not changed.
- iOS Release build passed. Final installed development 1.0 (53): `ios-a225b0ed8154467c`. UI checks passed for three Text→Voice cycles followed by recording, early startup cancellation followed by another recording, and date-setting off→on→restart→off→restart persistence.
- The private recording ran through the actual iPhone ASR→Index→speech pipeline with repair disabled and enabled. Recognition took 0.981 and 2.596 s respectively (+1.615 s); enabled produced the intended date/time and translation, disabled retained the original merged output. Both runs were nominal thermal. These are imported diagnostic fixtures, not a new live acoustic accuracy test. Temporary diagnostic files were restored byte-for-byte, saved settings were unchanged, preprocessing remains on and date repair off. The temporary UI runner was removed; normal app launch passed.
- The standalone Mac candidate passed signature and dependency checks (161 Mach-O files; no external non-system dependency/RPATH or deployment-target mismatch). Development 0.6.7 (60), `mac-d3db01dbe253a9bd`, replaced the installed app without a rollback copy. Installed executable/identity hashes matched and ordinary launch passed. Model files and saved data were not replaced. DMG/ZIP and Store packages were not refreshed in this task.
- Project validation: 143 tests passed. Localization: all 674 entries passed RU/EN/ES/TR coverage, placeholders and UI literal checks. Android generated dictionaries match the shared catalog.

No Store upload is part of this change. Native audio-engine startup remains the limitation described above. Android's system service returned a transient disconnection during an initial support check; explicit retry passed without a code change. Failure keeps microphone readiness false rather than claiming the service is prepared.

Final Android app/inference builds and instrumentation APKs passed; 139 JVM tests passed without failures or skips. Both lint checks report zero errors (existing app 55 warnings/3 hints, inference 4 warnings). Final Pixel lifecycle suite passed four cases; settings persistence and real native/service preload checks passed three cases. Installed development 0.4.6 (21) matches APK SHA-256 `bc601884501278b50d0ebfd7127cfd3f8762575f1b87f1c5a81f7249c1c57cab`. Saved preferences match the initial snapshot exactly, date repair is effectively off, preprocessing on; brightness and timeout were unchanged. Introduced native fixtures were removed and the ordinary app reopened.
