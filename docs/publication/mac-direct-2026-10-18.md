# Mac direct packages 0.6.8 (61) — 18 October 2026

Updated both local DMG/ZIP variants from the current sources: modern macOS 27+ and the separate macOS 15–26 compatibility package. Both include recognition preparation before microphone availability, optional date/time correction off by default, complete streamed speech and the latest Image paragraph reconstruction, short-line correction and diagnostics-only recognition/translation times. The version is incremented to **0.6.8 (61)** so the prior releases remain distinguishable.

| Package in `dist/macos` | Bytes | SHA-256 |
|---|---:|---|
| `Kat-translator-0.6.8-build61-mac-arm64.dmg` | 594258592 | `5b0a6ce455fa95b6a50ea19c49489155378886e365e65d916b4ba0d3b8aa8fbd` |
| `Kat-translator-0.6.8-build61-mac-arm64.zip` | 382203664 | `e16328edef650a5d856b0deadb7ed7916e682f225def801f0f69eb26b3b106dd` |
| `Kat-translator-0.6.8-build61-mac-arm64-macos15-26.dmg` | 570009372 | `ff6fddf68db83a838b4a0d07f839ec45473112eb909cd8088b02d2de793aec72` |
| `Kat-translator-0.6.8-build61-mac-arm64-macos15-26.zip` | 368111275 | `38844ebb1eb4666362b8b0aa7437707def57d8dad0d5a886034243e41fcd40b5` |

Both SHA256SUMS sidecars were regenerated and independently checked. ZIP extraction and read-only DMG mounting verified **25,199 modern / 25,121 compatible file/link entries** against their respective signed staging apps, including file hashes, permissions and symlink targets. DMG checksums and deep/strict app signatures passed. XCTest bundles are absent; the image/timing/date-setting code is present, and packaged MLX Python code matches source.

Source identities: modern **mac-83a7b28d8b88445e**, compatible **mac-557c23bc9f4e4c20**. Dependency audits checked **161 / 83 Mach-O files**, found no external non-system library dependencies/RPATHs and no components requiring an OS newer than each declared minimum. Both variants retain the same Apple Development signing identity as the installed application; they are not Developer ID signed or notarized.

All 143 project validation tests passed, including bilingual documentation/version parity. An initial documentation check caught a version-table formatting mismatch; it was corrected before the successful final run.

The compatibility build passed two real-app tests on the available macOS 27 machine: OCR/import → Index translation with a complete paragraph and nonzero diagnostics timings; packaged MLX routing/cancellation/limits. This does not establish acceptance on a physical macOS 15–26 installation. The [earlier image and UI checks](../benchmarks/mac-image-paragraphs-2026-10-18/README.md) apply to the unchanged image implementation; they were not repeated as a new modern runtime benchmark. An initial packaging attempt stopped because more than one signing certificate was available; the final packages explicitly use the installed app's certificate.

## Retention and scope

Keep at most three complete releases per distribution line, with both DMG and ZIP and their checksums: modern **59/60/61**, compatible **53/61** (only two releases exist). No older direct release exceeds the limit, so none needed deletion. All **878 prior distribution hashes** remained unchanged. Verified temporary extractions/staging copies were removed and all DMGs unmounted; models, dependencies and user data were preserved.

The installed Mac application remains the already verified corrected **0.6.7 (60)** copy; this task refreshes the distributable packages. iOS 54 / Mac Store 76 uploads and review state are unchanged. The packages remain local and outside Git. [Machine-readable checks](mac-direct-2026-10-18.json).
