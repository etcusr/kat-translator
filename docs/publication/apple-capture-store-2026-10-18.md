# Apple capture and Mac image release — 18 October 2026

**iOS 1.0 (54) and Mac App Store 1.0 (76) were verified and uploaded to App Store Connect.** Both upload commands finished successfully. Apple processing, installation through TestFlight and acceptance of those Store-delivered applications are not confirmed. No App Review selection, submission or listing change was made.

## Included behavior

Both releases include recognition preparation before microphone availability, safe recognition release on Text/Camera, the saved date/time repair setting off by default, and preserved during-recording processing. iPhone adds input-only AudioQueue capture with first-buffer readiness; Whisper models/decoding and voice quality settings are unchanged. The earlier complete streamed-speech and contextual ordinal fixes remain included.

Mac 76 additionally reconstructs still-image paragraphs before translation, cleans the editable translation's soft wraps/extra whitespace, displays OCR and translation times only with diagnostics enabled, and resumes images imported before tab preparation finishes. iOS 54 was built and uploaded before these Mac Image changes; its camera grouping is unchanged.

## Checks

| Check | iOS 54 | Mac 76 |
|---|---:|---:|
| Release archive / distribution export | PASS | PASS |
| Matching valid Mach-O signatures | 72 | 154 |
| Valid distribution profiles | 2 | 1 |
| Privacy manifests | 9 | 9 |
| Notice documents checked | 46 | 46 |
| Loading clips matched to source | 13 | 13 |
| Temporary test bundles/hooks absent | PASS | PASS |
| Successful upload | PASS | PASS |

The iOS app and widget both report 1.0/54; deployment metadata passed for 70 embedded frameworks. Its increased-memory entitlement and AudioQueue path were verified. The Mac app reports 1.0/76, macOS 27+, inherited sandbox permissions for both Python helpers, no external non-system library dependencies/RPATHs and no resource-bundle identity/signature collision. The installer signature was separately verified. The final Mac executable contains the image timing/layout code, and its packaged MLX script matches source. Package hashes and build identities are in the [machine-readable result](apple-capture-store-2026-10-18.json).

Project checks: **143 PASS**. Image-change checks: OfflineCore **326 tests, 2 opt-in skips, no failures**, **2 Mac runtime tests**, **1 UI test with diagnostics on/off**, and a final private-image app import, all passed. The final import followed the short-line glyph-height correction and retained complete paragraphs without mixing posts or repeating the final word. Two supplied image probes and synthetic layout/timing controls are described in the [image report](../benchmarks/mac-image-paragraphs-2026-10-18/README.md). Those checks exercised a development Mac application and local model runtime, not a Store-installed copy.

Prior device evidence: [recognition lifecycle/date setting](../benchmarks/date-setting-capture-2026-10-18/README.md) and [iPhone microphone startup/acoustic controls](../benchmarks/ios-microphone-start-2026-10-18/README.md). The measured first PCM improvement from about 1.40 to 0.28 seconds and the two complete acoustic phrases are earlier development-device results, not a new TestFlight measurement.

## Upload details and limits

Xcode reported 70 missing prebuilt-library dSYM warnings for iOS and 153 for Mac. These did not prevent successful uploads; they limit symbolication for the affected libraries. Main application symbol files are present in the retained archives.

Current signed archives and distribution IPA/PKG files are retained locally. Direct Mac DMG/ZIP, iPhone/Pixel installations and Android distribution packages were not replaced by this Store task. The Mac development application was separately [refreshed and launched](../benchmarks/mac-image-paragraphs-2026-10-18/installed.md) at the owner’s request. App Review build selection remains with the owner.
