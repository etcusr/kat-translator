# iPhone playback interruption fix — 14 October 2026

The source now prevents idle audio cleanup from deactivating another player's process-wide audio session. SpeechPlayer also releases its pending operation with an error when the session is interrupted or its engine configuration changes; the next explicit playback creates a fresh engine.

## Evidence and cause

On the connected iPhone, a one-second PCM signal reproducibly stopped and never completed after calling `stop()` on an unused SpeechPlayer and `cancel()` on an unused AudioRecorder. The pre-fix test failed after its three-second bound. Both methods unconditionally deactivated AVAudioSession, even when they had never activated it. The main AppModel's memory cleanup can reach these methods while another pipeline is playing. Apple documents that [deactivating a session stops its running audio objects](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:options:)). Ignoring the resulting error does not preserve playback.

A second pre-fix test posted a session interruption: the pending playback did not finish promptly. Playback previously depended solely on the `.dataPlayedBack` callback. [Engine configuration changes](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification) can stop/uninitialize the engine. Teardown now runs asynchronously on MainActor, scoped to the observed engine, rather than on its internal notification queue.

The recorder tracks successful session activation separately from engine allocation, so failed setup before engine assignment still releases its own session. Idle cleanup leaves it alone. These are demonstrated defects; the earlier intermittent error1852797029 lacks a complete historical trace, so every historical occurrence is not assigned to this mechanism.

## Validation

- Before the fix: two focused device tests failed as expected (idle cleanup and interruption handling).
- After the fix: six device tests passed in79.199s: idle cleanup, interruption/error/restart, six playback cycles, RU/DE/RU Auto routing with real ASR/MT/TTS, Russian→Thai translation/speech, standalone Thai Wayu.
- Second run of the previously unstable Auto and Russian→Thai cases: two passed,48.184s and16.389s.
- Mac shared player: pause/resume/speed/stop regression passed in2.035s, in the isolated test app. Installed Mac app unchanged.
- OfflineCore:272 tests,270 passed,2 opt-in skips,0 failures.
- Normal iOS Release development archive succeeded. It retains version1.0/build50 for this source validation; it is distinct from the unchanged distribution IPA50. New numbered store packages and TestFlight are a later release step.

Physical incoming calls/Bluetooth changes were not exercised; the interruption test posts the system notification. The tests use fixture speech, not the microphone. Xcode still reports synchronous audio activation latency warnings; this task does not migrate to the newer OS-only asynchronous API. Separate radio-off, background-download and network-trace acceptance was removed from the release queue at the owner's request, not marked passed.

Detailed private logs, result bundles and preservation snapshots remain in `.build/ios-playback-fix-2026-10-14/`, outside Git.

## Device restoration

The fixed normal development archive was installed and launched without XCTest. All40 original preferences and six history files were preserved (semantic comparison for JSON). All8,801 model/document paths remained; only four `.verified.json` receipts changed size. No original non-receipt file sizes changed and no test download leftovers remained. Store IPA50/PKG69 were not replaced.
