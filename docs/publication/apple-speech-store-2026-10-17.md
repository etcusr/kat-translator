# Apple speech release — 17 October 2026

**iOS 1.0 (53) and Mac App Store 1.0 (71)** package the October 17 speech corrections: drain every synthesis fragment, retain exact whitespace between streamed sentences, expand Russian ordinals using context, and provide partial output from the default Mac MLX translator. They also include the earlier microphone/memory-pressure fixes, tap recording defaults, four-thread Piper and current 13 loading clips. Voice weights and translation settings are unchanged.

## Fresh package verification

Both Release archives and App Store exports passed. The exported packages were extracted and checked independently before uploading.

| Check | iOS 53 | Mac 71 |
|---|---|---|
| Mach-O signatures and matching distribution signer | 72 PASS | 154 PASS |
| Distribution profiles | App + download widget PASS | App PASS |
| Privacy manifests / license documents | 9 / 46, source bytes match | 9 / 46, source bytes match |
| Loading clips | 13, source bytes match | 13, source bytes match |
| Platform checks | 70 framework deployment checks; increased-memory entitlement retained | Sandbox and inherited helpers; no external non-system dependencies/RPATHs |
| Development test bundles / removed clip / compiled OpenSSL, rustls, BoringSSL | Absent | Absent |

The Mac package's `index_mlx.py` matches the corrected source bytes. App/widget versions match on iOS. All 143 Python project-validation tests passed. The first run exposed stale version documentation and a build-membership fixture missing the already registered streamed-speech integration test; both were updated and the complete suite passed. The first signature check lacked access to system certificate validation in the restricted environment; the full check with that access passed.

[Package identities, SHA-256 and check results](apple-speech-store-2026-10-17.json). Upload re-signs the same verified archive; upload bytes may differ from the saved local export. No new rollback copy was created.

## Upload and limits

Xcode confirmed `Upload succeeded` and `EXPORT SUCCEEDED` for both iOS 53 and Mac 71. Missing dSYM warnings for prebuilt libraries limit crash symbolication but did not block either upload; counts are retained in the verification record.

Apple processing, TestFlight installation and store-package acoustic acceptance are not confirmed by upload. The owner selects the builds and manages App Review; this task did not change the review submission or listings.

Earlier development-device verification remains separate: [iPhone speech checks](../benchmarks/iphone-speech-correctness-2026-10-17/README.md), [Mac installation and runtime checks](../benchmarks/mac-speech-install-2026-10-17/README.md), [implementation and regression checks](../benchmarks/apple-speech-correctness-2026-10-17/README.md). Those runs are not new TestFlight tests. Unknown ordinal contexts remain unchanged; already played text cannot be retracted after a model rewrites its prefix. No all-language, Bluetooth or thermal-stress acceptance is claimed.

The modern direct Mac [DMG/ZIP](../benchmarks/mac-speech-install-2026-10-17/packages.md) were refreshed separately as 0.6.7 (60). The separate macOS 15–26 compatibility packages remain unchanged.
