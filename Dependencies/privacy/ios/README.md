# iOS framework privacy declarations

**English** | [Русский](README.ru.md)

These manifests describe Kat's pinned iOS runtime configuration. They are installed into the **embedded app frameworks**, after Python extension conversion and Xcode framework embedding, by `scripts/install-ios-privacy-manifests.py`. Modified frameworks are re-signed before Xcode signs the app. Vendor XCFrameworks and their downloaded checksums remain unchanged. macOS packaging is separate.

| Framework | Declaration | Evidence and scope |
|---|---|---|
| OpusRuntime | No required-reason API entries | Repackages SentencePiece with Abseil/Protobuf-lite; no matching API imports in the shipped framework. |
| Python 3.13.14 (Python-Apple-support 3.13-b14) | FileTimestamp `C617.1`; SystemBootTime `35F9.1` | CPython file metadata/imports inside the app container; monotonic clock for runtime timers and elapsed intervals. Kat initializes an isolated interpreter with bundled module paths in `shared/native/app/Speech/WayuFrontend.c`, and calls the packaged Wayu frontend. |
| TranslationRuntime | FileTimestamp `C617.1` | The linked cpp-httplib object contains `FileStat`/mmap and server file helpers using `stat`/`fstat`. Disassembly identifies those callers; this does **not** show a running HTTP server. Kat uses local model files through its translation adapter. The declaration restricts file metadata use to the app container. |
| OmniVoiceRuntime | FileTimestamp `C617.1` | `gguf-weights.h::gf_load` calls `fstat` to get model size before mmap. Disassembly confirms calls from codec/TTS loading. Models are in the app container. |

All four declare no tracking, no tracking domains and no collected data types. These are library declarations for this integration, not a substitute for App Privacy answers, traffic testing or third-party download-service disclosures.

## Offline Python packaging

`scripts/bundle-wayu-python.sh` copies the pinned standard library, then runs `scripts/prune-ios-python.py` before converting extensions to frameworks. The unused `_ssl` and `_hashlib` extensions (which embed OpenSSL) are excluded. Stale frameworks and module placeholders from incremental builds are removed too. Built-in hash modules remain; model downloads and integrity checks use URLSession and CryptoKit, independently of Python.

This runtime supports the bundled offline Wayu frontend, not arbitrary Python HTTPS clients or OpenSSL-only hash/KDF functions. Vendor archives remain unchanged. See the [removal audit and runtime-test limits](../../../docs/publication/ios-openssl-removal-2026-10-14.md). The [earlier five-framework audit](../../../docs/publication/privacy-frameworks-2026-10-14.md) describes the superseded package with OpenSSL.

## Python disk-space symbols

CPython imports `statfs`/`fstatfs` through `os.statvfs`/`os.fstatvfs` in [posixmodule.c](https://github.com/python/cpython/blob/v3.13.14/Modules/posixmodule.c). No calls to these wrappers or `shutil.disk_usage` were found in the packaged Wayu Python sources. The app's visible storage/download checks are implemented in Swift and already declared by the app manifest. We do **not** add `E174.1`/`85F4.1` to Python without a matching use. The unused standard-library entry points remain in its binary: local symbol inspection cannot guarantee App Store processing will accept them. If Apple flags this category, investigate pruning/rebuilding the unused API or a real call path instead of inventing a purpose.

Monotonic timing implementation: [CPython pytime.c](https://github.com/python/cpython/blob/v3.13.14/Python/pytime.c). Apple reasons: [API categories and approved purposes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). Re-signing embedded frameworks preserves app signing integrity; it does not establish an upstream SDK vendor signature or constitute Apple's validation.

## Updating dependencies

Review these declarations when dependencies or call paths change. An unexpected existing manifest causes a build failure rather than overwriting upstream disclosures. Missing frameworks or signing failures also fail the build. Do not use these files for a different Python integration without reviewing its actual behavior.

Validation: `python3 -m unittest discover -s scripts/validation -p 'test_ios_*.py'`. After archiving, verify manifest contents and strict signatures in the archive and exported IPA. [Dated verification](../../../docs/publication/privacy-frameworks-2026-10-14.md).

## Static SDKs and Swift packages

ONNX Runtime, Sherpa and FluidAudio declarations are installed separately by `install-sdk-privacy-manifests.py`; OfflineCore carries its own SwiftPM resource. See the [cross-platform SDK map and telemetry guard](../README.md). The latest iOS package has nine manifests, including the app.

The packaging installer also fills missing `MinimumOSVersion=18.0` in Kat-built OmniVoiceRuntime and OpusRuntime before re-signing. Their actual Mach-O deployment targets were checked as 18.0. Existing non-empty metadata is preserved. Before upload, run `python3 scripts/validation/check_ios_framework_metadata.py /path/to/exported.app` to compare all embedded frameworks with their binary targets and the app minimum.
