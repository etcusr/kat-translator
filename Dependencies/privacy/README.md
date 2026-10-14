# Apple privacy declarations

These files describe **Kat's pinned integration**, not every possible use of an upstream SDK. No collection or tracking is declared by these runtime components. The app manifests separately disclose download-host processing (coarse IP-derived location, network pseudonymous identifier, download interaction and technical diagnostics). See the [assessment and questionnaire mapping](../../docs/publication/model-download-privacy-2026-10-14.md); this is not collection by the local runtime SDKs. Review this set whenever dependencies, call paths or data practices change.

## Repackaged listed SDKs

Apple's [SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/) cover Abseil and Protobuf, including wrappers which repackage them. A scan of the actual iOS48/Mac67 binaries confirmed them; source archives alone were not used as proof. `cabsl`/`fabsl` in NumPy are math functions, not Abseil. A llama.cpp build-option error message mentioning OpenSSL is not an OpenSSL implementation.

| Component | Actual inclusion | Manifest placement |
|---|---|---|
| OpusRuntime | SentencePiece 0.2.1 with bundled Abseil/Protobuf-lite | Inside its framework on both platforms |
| ONNX Runtime | iOS static library in app; Mac `libonnxruntime.dylib`, including Abseil/Protobuf | Separate `ONNXRuntimePrivacy.bundle` |
| Sherpa ONNX | iOS static library; Mac `libsherpa-onnx-c-api.dylib`, with tokenizer/runtime code including listed dependencies | Separate `SherpaOnnxPrivacy.bundle` |
| Mac SentencePiece | Both IndexPython and OpusPython `_sentencepiece` extensions contain Abseil/Protobuf | Separate `SentencePiecePrivacy.bundle` for both copies |
| Mac Python Protobuf | IndexPython `google/_upb/_message` | Separate `ProtobufPrivacy.bundle` |
| Mac PyTorch | `torch/lib/libtorch_cpu.dylib` embeds Protobuf; `libtorch_python` consumes it | Separate `PyTorchPrivacy.bundle` |

Static archives and bare dylibs/extensions do not have their own resource location. Their named codeless resource bundles carry the disclosures alongside the consuming app. This avoids flattening several `PrivacyInfo.xcprivacy` files over each other. The integration map is explicit in `scripts/install-sdk-privacy-manifests.py`. Apple's processing of this package layout still needs confirmation; no upstream-vendor signature or Xcode-generated aggregate report is claimed.

## API and collection scope

- iOS ONNX/Sherpa: `FileTimestamp / C617.1`. Their linked `stat`/`fstat` paths open local model/tokenizer files in the app container. No disk-space reason is inferred from a different platform's dylib.
- iOS OpusRuntime: no required-reason API imports found in this framework; it still needs a manifest for repackaged listed SDKs.
- iOS FluidAudio: `FileTimestamp / C617.1` for `ModelCache.attributesIfPresent`, `FileDownloader` and temporary audio files. Kat uses `AsrModels.loadLocal`, not the SDK's network download convenience API. Its declaration is installed into the existing `FluidAudio_FluidAudio.bundle`.
- OfflineCore: its SwiftPM resource manifest declares `SystemBootTime / 35F9.1` for elapsed synthesis/processing time and `UserDefaults / CA92.1` for Kat's own preferences. These values remain local. The package resources are included by SwiftPM on both platforms.
- Native macOS has a separate data-collection declaration, with an empty required-reason list, for the app (`macos/App.xcprivacy`) and the listed runtime wrappers (`macos/NoCollection.xcprivacy`). Apple scopes the required-reason requirement to iOS/iPadOS/tvOS/visionOS/watchOS; it does not exempt Mac SDK/data-collection declarations. OfflineCore's shared resource remains truthful on both platforms.
- Existing iOS Python/TranslationRuntime/OmniVoice declarations and the unused Python disk-space symbol caveat remain in [ios/README.md](ios/README.md).

The widget contains no matching required-reason API or third-party runtime in this audit. Whisper, llama.cpp, OmniVoice, FluidAudio, MLX, NumPy, tokenizers and PyTorch are not themselves named on Apple's list; embedded listed dependencies are assessed separately. Loading-animation JSONs/MP4s do not imply a linked Lottie SDK.

## Telemetry is disabled before initialization

The shipped Mac ONNX 1.30 library includes Microsoft's 1DS provider. In the [pinned upstream documentation](https://github.com/microsoft/onnxruntime/blob/v1.30.0/docs/Privacy.md), API-level `DisableTelemetryEvents` does not suppress the initial process event. `shared/native/app/Privacy/InferencePrivacy.c` sets `ORT_DISABLE_TELEMETRY=1` once, before every first ONNX/Sherpa creation entry. Failure prevents SDK initialization. The flag prevents logger/uploader/device-ID creation in this version. Existing API-level disables remain in OCR/Wayu.

Index sets HF offline and disable-telemetry before importing its dependencies. OPUS sets HF offline before imports; the packaged `huggingface_hub.utils._telemetry.send_telemetry` returns immediately in that mode. Both use local model paths. SDK code with network capabilities remains present; this audit concerns how Kat invokes it, not an assertion that no binary contains networking functions.

## Packaging and validation

- iOS dynamic framework installer runs after embedding and Python conversion; affected frameworks are signed after copying their manifests. The SDK-resource installer follows in the same build phase.
- Mac installer runs at the end of runtime packaging, before the app signature. It re-signs the modified Opus framework. New codeless bundles remain unsigned, sealed by the app signature, with unique identifiers and no executable/NSServices keys.
- Both installers validate all required inputs and conflicting existing SDK manifests before modifying bundles. Kat owns its Mac app manifest and replaces its previous declaration during incremental builds; its collection entries must match the iOS app declaration. Future upstream disclosures are not silently replaced. A signing error fails the build.
- Vendor archives and XCFramework inputs are unchanged. App distribution signatures establish package integrity, **not** a supplier's original SDK signature. Upstream signature/provenance and App Store server processing remain separate acceptance steps.

Run `PYTHONPATH=scripts/validation python3 -m unittest scripts.validation.test_inference_privacy scripts.validation.test_ios_privacy_manifests scripts.validation.test_sdk_privacy_manifests`. Inspect all manifests and strict signatures in the final exported IPA/PKG, not just sources. [Dated audit](../../docs/publication/apple-privacy-sdk-2026-10-14.md).
