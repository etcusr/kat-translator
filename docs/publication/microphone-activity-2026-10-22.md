# Apple microphone activity — 22 October 2026

Implemented a shared lime bar backdrop behind the record/stop button. Rounded bars show recent measured loudness, with 10–48% opacity and fading edges; the opaque button stays legible. Quiet input collapses the bars, pause clears them, and Reduce Motion fixes their height and disables interpolation. The decoration neither handles taps nor changes control layout. VoiceOver receives the detected sound/speech/quiet state through the status label.

`RecordingSink` computes a read-only RMS level from existing normalized PCM, reuses Silero speech detection, and publishes a lock-protected snapshot to the existing 100 ms recorder timer. Values expire after 350 ms. No extra capture session, inference model or persistent setting is introduced. Recognition and translation algorithms are unchanged.

## Checks

- OfflineCore: 386 tests, 3 expected skips, zero failures; includes silence/nonfinite/clipping/unchanged-input checks.
- Mac runtime: 2 tests passed in the final bar version. The actual RecordingSink preserved captured PCM exactly through measurement/pause/resume; stale readings reset. Five rendered states kept identical geometry. Native render attachments were visually inspected.
- Release builds: iOS and macOS passed. Localization: 705 strings passed. Paired documentation checks: 2 passed.
- Live Mac automation reached recording and played a synthetic phrase, but its accessibility query read an empty label; the underlying static text exposes a value. This attempt is not evidence of successful live VAD acceptance. Earlier screenshot capture was denied by macOS. No privacy permission was changed.
- Visual rendering checks do not establish speech recognition quality, thermal performance or exhaustive microphone/background behavior.

## Local deployment

Development iOS 1.0.1 (72) and macOS 0.6.9 (67) installed in place and launched. Mac signing requirement matches the prior installed app. iPhone retained 1,174 files with identical paths/sizes in the checked app-support subtree; Mac retained 2,132. These are metadata checks, not full content hashes or a full preferences comparison. No model IDs/paths or settings migration changed. Full iPhone preferences were not exported.

No Store upload, review submission or Git push. Raw logs, native render attachments and device metadata remain private under `.build/microphone-activity-2026-10-22/`.
