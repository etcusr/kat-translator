# Signed speech SDK distributions and release 51/70

## SDK verification

Kat's copies of all three speech XCFrameworks now have timestamped Apple Development signatures. Strict/deep verification passes. These are **Kat distributor signatures**, not signatures issued by the upstream developers. Before and after signing, all original files were compared with the checksum-pinned official release ZIPs: iOS Sherpa:9, iOS ONNX:37, Mac Sherpa:5; no payload changes. The original unsigned copies are retained locally for rollback.

`scripts/sign-verified-speech-sdks.py` performs this check before signing separate output copies, verifies the signatures and checks the original payload again. It fails on changed archives, changed/injected files, symlinks or an existing output directory. The signed copies were explicitly promoted to the project's SDK input directories. Re-fetching upstream ZIPs requires repeating this signing step.

## Binary to source mapping

| Binary | Embedded evidence | Corresponding source |
|---|---|---|
| iOS Sherpa1.13.8 | `793c2405`, release date10September2026 | `793c2405ada0e9ee55a55037fa2d56111b8e7206` |
| Mac Sherpa1.13.8 | Exported version/git functions report the same revision | Same source archive |
| iOS ONNX1.28.1 | Build info contains `5181af9` | Official1.28.1 tag: `5181af9bef60f46194ec30506855d74b6e6a96ff` |
| ONNX statically included in Mac Sherpa1.13.8 | Exported version1.28.2 and build info `33ca96282` | Official1.28.2 tag: `33ca9628233dc8f002435e868d4c2e9f82766ca1` |

The old Sherpa lock pointed at a different commit with the same version label. It is corrected and the exact11.6MB release source archive has been added to the source kit, bringing it to615 checked inputs. All dependency CMake recipes in that revision match the previously collected recipe files, including the eSpeak/Piper pins. The original Sherpa license bytes match the retained notice; its source URL now points at the actual release revision. [Evidence](../licensing/2026-10-14/sdk-provenance.json).

This establishes release origin, embedded build identity and source availability. It is not an independent byte-identical reproduction or a supplier build attestation. Neither of those stronger claims is used as a blanket prerequisite for preparing and uploading this release. Existing broader Python/model/media license questions remain documented separately and are not reported as resolved by SDK signing.

The separately rebuilt Opus candidate has not been substituted into these packages: the existing tested Opus runtime remains in use. No new inference implementation is introduced by the speech SDK signing step.

## Release validation

iOS1.0(51) and Mac1.0(70) include the previously device-tested audio-session fix, current privacy manifests and46 license documents. Final export, package checks and upload results are recorded below when completed. Earlier radio-off/background/network checks remain waived, not passed. Device tests of the audio fix are recorded in [the playback report](ios-playback-fix-2026-10-14.md); an archive/export is not TestFlight acceptance.

## First iOS upload and correction

Apple rejected the first iOS51 upload before ingestion because CMake-generated OmniVoiceRuntime/OpusRuntime framework plists omitted `MinimumOSVersion`. Their actual Mach-O deployment targets are both18.0. Packaging now fills that missing metadata before signing, without modifying the executable; existing non-empty values are preserved. The regression failed before the fix and passed afterward, together with all10 framework-packaging tests. A separate exported-app validator checks every framework against the binary deployment target and app minimum. Missing dSYM warnings for prebuilt libraries are recorded separately from the validation errors; the available symbols were retained. The rejected archive/export remain local evidence and must not be selected for upload.

Final local export validation: **138 Python tests PASS**, **615 source inputs verified**, **72/154 signed Mach-O binaries**, **9 manifests and46 license documents per platform**. The corrected iOS export also passes binary/plist deployment checks for all70 embedded frameworks. Local artifact hashes and package details are in the [JSON record](signed-sdks-release-2026-10-14.json). Additional Sherpa sources and mapping were published; both GitHub digests match, and the mapping was downloaded anonymously and compared byte-for-byte. [Supplement delivery evidence](../licensing/2026-10-14/source-supplement-publication.json).

## Upload result

**Both uploads succeeded: iOS1.0(51) and Mac1.0(70).** Xcode reports `Upload succeeded` and `EXPORT SUCCEEDED` for each. The iOS retry used the corrected archive. Missing debug-symbol warnings for prebuilt libraries do not prevent this upload; detailed crash symbolication for those libraries remains limited. Local exports and uploads originate from the same checked archives, with separate distribution-signing runs. App Store processing, TestFlight availability and App Review approval are not inferred from upload success. The owner will select the builds and submit for review. No submission was made by this task.
