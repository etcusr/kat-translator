# iOS 1.0 (55): original recording volume — 18 October 2026

Built, verified and uploaded iOS **1.0 (55)** with the accepted original-recording volume fix. The owner checked the installed development 54 and reported that it appears correct. Source identity of the Store archive/export: **ios-77f05165ef0bac32**. Xcode reported **Upload succeeded** and **EXPORT SUCCEEDED**. Apple processing and TestFlight acceptance are not confirmed; App Review selection/submission remains with the owner.

The fix adjusts only saved original audio used for replay, export and new history entries. Whisper/VAD input, capture startup and synthesized speech keep their previous behavior. The [implementation and file-level checks](../benchmarks/apple-original-level-2026-10-18/README.md) describe the bounded gain, AAC headroom and limits. Before packaging, the implementation passed 330 core tests with two unrelated opt-in skips, including the private AAC probe; this release reran all 143 project validations. User verification is not an independent measured acoustic comparison.

## Final package checks

- Release archive and App Store export succeeded; application and widget are both 1.0 (55).
- Deep/strict app signature and all **72 binary signatures** passed; signers match the distribution profiles.
- **2 App Store profiles**, no development entitlement, increased-memory entitlement retained.
- **70 framework deployment checks**, **9 privacy manifests**, **46 notice documents**, **13 loading clips** checked; no XCTest/private fixtures in the package.
- Exported executable code section and build identity match the freshly built archive. Optimized Swift helper names are stripped, so symbol-name presence is not used as proof.
- Existing encryption packaging checks passed; encryption metadata is unchanged.
- Xcode reported **70 missing prebuilt-library dSYM warnings** during upload. Upload succeeded; those libraries retain limited crash symbolication.

Local artifact: `dist/ios/store/Kat-translator-1.0-build55.ipa` — **68456068 bytes**, SHA-256 `b76ca000da4813673f8aa51c41885f7ff7b97f033c9c0c661305472ef3e59425`. Keep latest three Store distributions **53/54/55**; removed only the old 52 IPA and its checksum after successful upload, with 53/54 hashes unchanged. The archive and compact verification logs are retained locally, outside Git. [Machine-readable summary](ios-original-volume-2026-10-18.json).

No new device installation in this release task: the owner-tested development 54 remains on iPhone. Mac/Android installed apps and their distribution packages were not refreshed. No App Review state change.
