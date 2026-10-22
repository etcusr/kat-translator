# iPhone 17 Pro Simulator navigation — 22 October 2026

Installed ARM64 iOS 27.0 (24A434) and ran the normal Kat iOS app on the exact iPhone 17 Pro simulator profile. The separately installed iOS 27.1 runtime and Duo devices were retained.

Two native XCTest cases passed with zero failures or skips: all Settings categories and voice search, full-width row taps, Quick setup, source/target language search, Voice/Text/Camera transitions, history, and text retention after mode changes and Home/return. Screenshot attachments are retained in the private xcresult. No models, microphone capture or inference were used; physical-device behavior and performance are not established by these checks.

Repeat using [the runner](../../scripts/simulator/README.md). The runner targets only its named simulator, verifies the exact device model, and requires both tests to pass. Logs and screenshots remain ignored under `.build/KatSimulatorUITests/runs/`.

## Seeded models and runtime check

APFS clonefile succeeded for 729 files (8,362,892,514 logical bytes): Index 9B/2B, Whisper Q8, Denis and LJSpeech archives and extracted packages. No full-copy fallback or shared directory links. The package verifier rejects symlinked weights, so its safety checks remain unchanged.

Initial Whisper and Index runs crashed in MTLSimDevice mapped-buffer creation. Simulator-only CPU routing was added to WhisperBackend and the native TranslationRuntime default loader; the physical iPhone runtime file remained SHA-256 identical. After rebuilding only the simulator SDK, two tests passed: recognition/translation preparation reached an enabled record button; Index 2B translated «Привет, мир!» to «Hello, world!». No microphone/TTS playback or Index 9B inference acceptance is claimed. Results are simulator evidence, not phone performance.
