# Installed Mac residency update — 20 October 2026

Replaced `/Applications/Kat translator.app` with the verified main Mac build
**0.6.8 (61)**, source ID **mac-c1e1bb101392ada8**, from commit `0798013`.
It includes the configurable idle-unload timer and the optional Index 9B plain
chunk mode. The application was opened normally from Applications.

The candidate was signed with the same existing development certificate as the
previous installation. Its designated requirement matches the old application's
requirement exactly. Deep/strict signature verification passed before and after
replacement. The standalone audit checked **161 Mach-O files**: no external
non-system dependencies/RPATHs and no component above the declared macOS 27
minimum. No XCTest bundle is included.

All **25,206 file/link entries** in the installed bundle match the signed
candidate. The previous **0.6.7 (60)** application was retained at
`.build/mac-install-residency-2026-10-20/previous-0.6.7-build60.app`; all of its
25,206 entries match its pre-install snapshot. A failed replacement verification
would restore that copy automatically.

Before and after replacement, all **2,117 app-data entries** (18,664,790,312 bytes)
matched by SHA-256, including installed models and history. The installer moved
only application bundles. It did not copy, prune or modify the app-data directory.
All saved preference values were equal before replacement and after ordinary
launch; no preference keys were added. Local preference snapshots and private
file manifests remain ignored and are not included in Git.

[Sanitized installation checks](installed.json). The [earlier real-engine tests](README.md)
exercise this build's implementation; the installation check verifies the bundle,
data preservation and normal launch, not a new microphone/translation session.
No DMG/ZIP, App Store upload, TestFlight change or push was performed.
