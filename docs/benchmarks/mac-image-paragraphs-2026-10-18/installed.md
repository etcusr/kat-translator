# Installed Mac image update — 18 October 2026

Refreshed `/Applications/Kat translator.app` from the corrected sources. The direct development version remains **0.6.7 (60)**; its new source fingerprint is **mac-8378c215e7c13deb**. It includes paragraph reconstruction, the short-final-word correction, compact editable translation text and diagnostics-only OCR/translation timing.

A normal arm64 Release build succeeded. The staged application excludes XCTest bundles and was signed with the same existing development certificate as the prior installation. Deep/strict signature verification passed; the bundle audit checked **161 Mach-O files**, no external non-system dependencies/RPATHs and macOS 27 deployment compatibility. All **25,206 installed file/link entries** matched the verified candidate. Ordinary launch from `/Applications` passed, and all saved preference values were unchanged. Models and app data were not moved. No rollback copy was retained.

The [image tests and supplied-image comparison](README.md) exercised the same corrected source before this standalone installation. This installation check establishes bundle integrity and normal startup, not a new image translation run in the installed copy. Modern DMG/ZIP and macOS 15–26 compatibility packages remain the earlier releases; the independent Mac App Store 76 upload is recorded in the [Store report](../../publication/apple-capture-store-2026-10-18.md).

The DMG/ZIP packages were subsequently refreshed to 0.6.8 (61) for both profiles; see the [package checks](../../publication/mac-direct-2026-10-18.md).
