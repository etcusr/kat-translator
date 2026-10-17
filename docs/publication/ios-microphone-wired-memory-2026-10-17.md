# iPhone microphone: CoreAudio wired-memory failure — 17 October 2026

## Failure and cause

Kat 1.0 (51), with Index 9B loaded and memory saving off, repeatedly failed to start live microphone capture with `com.apple.coreaudio.avfaudio / 1852797029` (`nope`). Microphone permission and audio-session activation succeeded. The server stopped before delivering the first audio frame.

A live system-log stream, connected **after** the app launched, exposed the underlying failure. The earlier archived log contained only the final error and undecoded kernel messages. The relevant server chain was:

```text
HALB_IOBufferManager: wiredlog: mlock failure event seen.
AllocateBuffer: failed to lock the buffer, byte size 376832,
errno 35 Resource temporarily unavailable
IOWorkLoop: failed to start the hardware
AUIOClient_StartIO failed (1852797029)
```

The pinned ggml Metal implementation requests persistent residency for model/context buffers (`ggml-metal-device.m`, `ggml_metal_buffer_rset_init`) and refreshes residency after GPU work. This competes with CoreAudio for wired memory. Free allocation budget reported for the app is not the same as the system's remaining wired-memory budget: one failed capture reported approximately 2.1 GiB app footprint, 7.1 GiB resident memory and 3.9 GiB app allocation headroom.

The controlled run with only `GGML_METAL_NO_RESIDENCY=1` passed live microphone startup, keeping Index 9B loaded and memory saving off. Removing loading video, changing audio-session mode and selecting Whisper did not fix the baseline. A separate native capture control passed; the failure was not a blanket microphone-permission denial. These observations identify persistent Metal residency as the app-side trigger for the captured allocation failure. They do not establish that every historical error with the same generic code had this cause.

The existing `com.apple.developer.kernel.increased-memory-limit` entitlement remains enabled. It was verified in both the source entitlements and the signed development app installed for this check. The app allocation allowance does not guarantee that CoreAudio can lock an I/O buffer under persistent Metal residency pressure.

## Change

`apps/ios/OfflineTranslatorApp.swift` sets `GGML_METAL_NO_RESIDENCY=1` at startup, before any ggml Metal device is created. It uses the pinned runtime's existing supported path without explicit residency sets. Models stay loaded and inference continues to use Metal. No change to the user's memory-saving setting, model selection, audio category, recording buffer, or ASR implementation is required. macOS and Android startup remain unchanged.

Temporary recorder diagnostics, category switches and the video-isolation branch were removed. No vendor binary or model was modified. The installed result is a local development build 1.0 (51); existing App Store/TestFlight packages were not replaced or uploaded.

## Verification

- Baseline physical microphone probe: failed before the change; log evidence above.
- Runtime-flag control: passed with memory saving off.
- Normal application source with the startup fix: build passed.
- First UI regression: two fresh app launches, each with a real RU→EN Index translation followed by live microphone startup, pause/resume and an advancing recording timer; passed.
- Final explicit Auto/Ultra and Whisper regression: passed (one test, two fresh launches; translation, capture and pause/resume in each). Documentation parity: 2 passed; whitespace check passed.

The reusable opt-in test is `TranslatorUITests.testLiveMicrophoneWithWarmIndex`, enabled with `TEST_RUNNER_KAT_IOS_LIVE_MIC=1` when invoking `xcodebuild test`. It requires an unlocked physical iPhone, microphone permission and installed Index/ASR models. Launch-argument overrides disable history writes; capture is discarded by terminating the app. The caller must snapshot and restore preferences: recognizer selection normalization persists its launch override. It tests live capture and GPU translation separately, not a complete spoken ASR→MT→TTS conversation. There is no long-duration, Bluetooth, thermal-stress or throughput comparison in this run.

Private device logs and XCTest bundles remain under ignored `.build/microphone-diagnosis-2026-10-17/`; they are not part of the public repository. Device verification compares preferences and file metadata, without reading personal translation/audio contents.

After all tests, the saved preferences were restored and compared with the pre-diagnosis snapshot: no value differences, automatic recognition restored and memory saving off. File metadata showed no original regular-file paths missing; model payload sizes were unchanged. History and verification metadata changed during the diagnostic session, so this is not a claim of byte-identical history or a content/hash audit. Temporary diagnostic apps were removed, log collectors stopped, and Kat was launched normally.
