# Refreshed Mac DMG/ZIP — 17 October 2026

The modern Mac distribution packages were regenerated from the installed corrected app, version **0.6.7 (60)**, source fingerprint **mac-c075be03543c17ac**. Existing package filenames were replaced; the version number is unchanged. Both now include the complete streamed-speech, Russian ordinal and MLX partial-output fixes described in the [installation report](README.md).

| Package in `dist/macos` | Bytes | SHA-256 |
|---|---:|---|
| `Kat-translator-0.6.7-build60-mac-arm64.dmg` | 586703591 | `43cc57d3911aa99b782427d636daa06429e2de77130dc8e9a60757352cf112ff` |
| `Kat-translator-0.6.7-build60-mac-arm64.zip` | 382157177 | `e68b085b2dde417ab5fe8f4376a1d9c75939436d401fe22ef93777ed16c578c9` |

The adjacent `Kat-translator-0.6.7-build60-mac-arm64-SHA256SUMS.txt` was regenerated and independently checked. Both app copies passed deep/strict signature verification. The DMG image checksum passed. All **25,206 file/symlink entries** in each extracted app matched the signed staging app, including file hashes, permissions, link targets and source identity. XCTest bundles are absent. Temporary extraction was removed and the DMG unmounted after verification.

Packaging retained the existing Apple Development identity. The standalone dependency audit passed for 161 Mach-O files. This is the modern Apple Silicon package requiring macOS27+, without Developer ID/notarization. The separate macOS15–26 compatibility package and App Store70 were not changed. No model weights or user data were added. Packages stay outside Git; runtime tests from the immediately preceding installation remain the runtime evidence, while the archive integrity checks above are fresh.
