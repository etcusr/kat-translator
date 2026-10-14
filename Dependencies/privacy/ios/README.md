# iOS framework privacy declarations

These manifests describe Kat's pinned iOS runtime configuration. They are installed into the **embedded app frameworks**, after Python extension conversion and Xcode framework embedding, by `scripts/install-ios-privacy-manifests.py`. Modified frameworks are re-signed before Xcode signs the app. Vendor XCFrameworks and their downloaded checksums remain unchanged. macOS packaging is separate.

| Framework | Declaration | Evidence and scope |
|---|---|---|
| Python 3.13.14 (Python-Apple-support 3.13-b14) | FileTimestamp `C617.1`; SystemBootTime `35F9.1` | CPython file metadata/imports inside the app container; monotonic clock for runtime timers and elapsed intervals. Kat initializes an isolated interpreter with bundled module paths in `shared/native/app/Speech/WayuFrontend.c`, and calls the packaged Wayu frontend. |
| TranslationRuntime | FileTimestamp `C617.1` | The linked cpp-httplib object contains `FileStat`/mmap and server file helpers using `stat`/`fstat`. Disassembly identifies those callers; this does **not** show a running HTTP server. Kat uses local model files through its translation adapter. The declaration restricts file metadata use to the app container. |
| OmniVoiceRuntime | FileTimestamp `C617.1` | `gguf-weights.h::gf_load` calls `fstat` to get model size before mmap. Disassembly confirms calls from codec/TTS loading. Models are in the app container. |
| `_ssl`, `_hashlib` (OpenSSL 3.0.18) | FileTimestamp `C617.1` | Byte-for-byte copies of OpenSSL's own declaration. Binary callers include configuration/file/certificate helpers and entropy helpers. Retaining a module does not itself establish that Kat sends data through it. |

All five declare no tracking, no tracking domains and no collected data types. These are library declarations for this integration, not a substitute for App Privacy answers, traffic testing or third-party download-service disclosures.

## OpenSSL provenance

Source: [OpenSSL 3.0.18 PrivacyInfo.xcprivacy](https://github.com/openssl/openssl/blob/openssl-3.0.18/os-dep/Apple/PrivacyInfo.xcprivacy). SHA-256 of each copied file: `aff9c890e7b9527243a47c281ba3658c37f1f9d676d63e02b2e36ba38c2af3ee`.

OpenSSL is licensed under [Apache-2.0](https://github.com/openssl/openssl/blob/openssl-3.0.18/LICENSE.txt). The declarations are retained without adding speculative categories. CPython's [upstream issue](https://github.com/python/cpython/issues/132006) documents App Store rejections for missing manifests in these extension frameworks. Our pinned Python packaging supports per-extension manifests but did not supply them.

## Python disk-space symbols

CPython imports `statfs`/`fstatfs` through `os.statvfs`/`os.fstatvfs` in [posixmodule.c](https://github.com/python/cpython/blob/v3.13.14/Modules/posixmodule.c). No calls to these wrappers or `shutil.disk_usage` were found in the packaged Wayu Python sources. The app's visible storage/download checks are implemented in Swift and already declared by the app manifest. We do **not** add `E174.1`/`85F4.1` to Python without a matching use. The unused standard-library entry points remain in its binary: local symbol inspection cannot guarantee App Store processing will accept them. If Apple flags this category, investigate pruning/rebuilding the unused API or a real call path instead of inventing a purpose.

Monotonic timing implementation: [CPython pytime.c](https://github.com/python/cpython/blob/v3.13.14/Python/pytime.c). Apple reasons: [API categories and approved purposes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). OpenSSL is on Apple's [SDK manifest/signature list](https://developer.apple.com/support/third-party-SDK-requirements/), including repackaged SDKs. Re-signing embedded frameworks preserves app signing integrity; it does not establish an upstream SDK vendor signature or constitute Apple's validation.

## Updating dependencies

Review these declarations when dependencies or call paths change. An unexpected existing manifest causes a build failure rather than overwriting upstream disclosures. Missing frameworks or signing failures also fail the build. Do not use these files for a different Python integration without reviewing its actual behavior.

Validation: `python3 -m unittest scripts.validation.test_ios_privacy_manifests`. After archiving, verify manifest contents and strict signatures in the archive and exported IPA. [Dated verification](../../../docs/publication/privacy-frameworks-2026-10-14.md).
