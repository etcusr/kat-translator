# Android voice results and playback controls — 17 October 2026

Voice mode now renders both translation and original cards before the first result. The original text has no collapsed state. During playback, the active card shows a cross with the accessible label Stop; stopping or natural completion restores the speaker. Paused playback remains stoppable. The other card retains its own playback action.

`KatApp.kt` renders the cards and action state. `TranslatorState.kt` exposes playback ownership through observable state and handles a stop request before the busy guard, so automatic speech can be stopped while the translation worker finishes bookkeeping. Cached audio remains available for replay. This change does not optimize voice generation or change ASR/translation models.

## Verification

- Before the UI fix: both new `VoiceResultPlaybackTest` tests failed on the Pixel — missing empty cards and the unchanged speaker action during automatic speech.
- After the fix: app/test APK builds, 107 unit tests (67 app + 40 inference), and lint passed. Lint retains existing warnings.
- Four physical Pixel 9 Pro checks passed in 19.584 seconds: both new tests, the updated original/translation visibility test, and the existing original-recording playback/export test.
- The automatic playback check runs actual OPUS translation and Piper synthesis from a supplied test phrase, then exercises stop, replay, paused stop and natural completion. This is not a live microphone test.
- All saved preference hashes matched before/after, including the history value. Test history/audio saving was disabled; the preference-restoration rule completed. The voice-result test screenshot was visually inspected.
- Documentation parity: 2 tests passed. Diff whitespace checks passed.

The rebuilt development APK was installed over Android 0.4.6 / code 21 without uninstalling or changing the version. No new signed/public release or push. Apple apps are unchanged. No synthesis-speed improvement, broad language-quality assessment, Bluetooth check or live-microphone acceptance is claimed. Private device logs and test images remain under ignored `.build/`.
