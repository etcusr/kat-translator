# Mac Store Python runtime — 23 October 2026

The Python/OpenSSL blocker is resolved. A local 1.1.0 (78) package exported successfully as the packaging check. The final candidate is **1.1.0 (79)**, including the [adaptive language rows](language-picker-layout-2026-10-23.md); its archive and runtime checks passed. Final package export succeeded; the installer certificate chain is valid. The signed package is retained at `dist/store/macos-1.1.0-79/Kat translator.pkg` ([size and checksum](2026-10-22/artifacts.json)). No package was uploaded and the existing Mac review was not changed.

## Runtime selection

`scripts/prepare-macos-store-python.py` builds **CPython 3.11.17** from the [official source release](https://www.python.org/downloads/release/python-31117/), pinned XZ SHA-256 `bfb74ad39efae27cda510f134ab408e00f9992c56851cfc0b1cdb5646da11599`. `_ssl`, `_hashlib` and the unused `_tkinter` extension are disabled at compile time. Standard-library hash implementations remain available. Deployment target is 15.0; the actual modern Store app still requires macOS 27.0, unchanged.

Only `profile(..., store=True)` uses this runtime. Direct modern and macOS 15–26 profiles retain the existing python-build-standalone runtime and the same model packages. Project generation and bundling use the same Store selector. Weights, package IDs, model paths, download logic and encryption declarations are unchanged. The existing archive guard still rejects OpenSSL/rustls/BoringSSL; no strings or symbols were hidden to bypass it.

The build validates the source archive checksum, expected Python version, absence of SSL/hashlib extension imports and built-in OpenSSL symbols, and basic stdlib/ctypes/hash functionality. Downloads remain in the native OS networking stack. Prepared runtime/build outputs are ignored by Git.

## Checks

- Final archive 79: successful; no XCTest bundles, inherited sandbox entitlements on helpers, no unexpected executable or duplicate resource bundle identity. Existing crypto guard passed.
- Bundle audit: **142 Mach-O files**, all arm64, no external non-system dependencies/rpaths, missing bundled dependencies, excessive deployment targets or mismatched signing teams. Deep strict signature verification passed.
- Packaged Python engine smoke: real **Index 9B MLX MTP2** RU→EN translation with 11 partial callbacks; **OPUS Metal FP16** in both RU→EN/EN→RU directions; **Wayu Thai** frontend produced 19 tokens. Index: “I would like to book a room at the hotel.” OPUS: “I'd like to book a hotel room.” / “Я хотел бы забронировать номер в отеле.” [Structured results](mac-store-python-2026-10-23.json).
- Profile invariants: 4 tests; Store archive failure handling: 5 tests; Index runtime: 4 tests; OPUS worker: 5 tests. Local Store metadata: 8 locales / 72 fields / 2 review notes; paired documentation parity: 2 tests.
- UI: four simulator capture tests and one Mac native language-sheet render test passed. Simulator and native Mac testing/inference ran sequentially; simulator is shut down.

The Store helper intentionally inherits its parent's sandbox and cannot be launched directly from a shell (the attempted direct launch terminated with “Process is not in an inherited sandbox”). The smoke test re-signs only a temporary executable copy without those entitlements and loads the archive's libraries/modules unchanged, using existing model files read-only. The archive itself is never modified. This proves runtime/import/inference compatibility, **not** full Store-sandbox/UI acceptance or an installed-user upgrade. It is not a speed benchmark or a broad quality comparison. No live microphone/audio playback was tested here.

## Reproduce and remaining release work

1. `python3 scripts/prepare-macos-store-python.py`
2. `KAT_MAC_STORE_VERSION=1.1.0 KAT_MAC_STORE_BUILD=<fresh-number> bash scripts/archive-macos-appstore.sh export`
3. Run `scripts/validation/check-macos-bundle.py` against the archived app and `scripts/validation/smoke-macos-store-python.py --app <archived-app> --models <existing-translation-packages> --output <local-json>`.

Local logs: `.build/mac-store-79.log`, `.build/macos-appstore/1.1.0-79/`, `.build/store-bundle-check-79.json`, `.build/store-runtime-smoke-79.json`. Build identity: `mac-0b53fa1c8be39790`. Full Mac Store screenshots, final installed-candidate acceptance and a later explicitly authorized upload/review remain separate work. Previous iOS 73/direct Mac 68 exports predate the language-row fix; regenerate them before claiming that UI change. Installed iPhone 72/Mac 67 and the older macOS Store review remain untouched.
