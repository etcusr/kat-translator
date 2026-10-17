# iOS 1.0 (52) — 17 October 2026

Release 52 packages the iPhone microphone and memory-pressure fixes (`3f624bb`, `5bb7161`), tap-to-start defaults and the current 13 loading clips. macOS and Android packages are unchanged.

## Package verification

Release archive and App Store export passed. The app and download extension are both 1.0 (52). The exported app retains `com.apple.developer.kernel.increased-memory-limit=true`; distribution profiles and all 72 Mach-O signatures passed verification. All 70 embedded frameworks passed deployment-metadata validation. Nine privacy manifests and 46 license notices match the current sources. Test bundles and the removed loading clip are absent. All 138 project validation tests passed after the version table was updated.

The exported package identity, SHA-256 and check counts are in [the verification record](ios-store-build52-2026-10-17.json). Upload re-signs the same archive; its distribution bytes can differ from the local export.

## Upload and acceptance

Xcode confirmed `Upload succeeded` and `EXPORT SUCCEEDED` for 1.0 (52). Missing dSYM warnings for prebuilt frameworks limit crash symbolication but did not block upload. TestFlight processing, installation and full acoustic acceptance remain pending. Earlier development-build checks are recorded in [the microphone report](ios-microphone-wired-memory-2026-10-17.md); they are not TestFlight acceptance.

The owner will select the new build and resubmit App Review. This release task does not change the current review submission. Bluetooth, thermal stress and all-language acceptance are outside this verification.
