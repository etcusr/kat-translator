# Source delivery, SDK provenance and remaining rights — 14 October 2026

## Follow-up: signed distributions and release source correction

The three SDK distributions now carry verified Kat distributor signatures with unchanged official payloads. The actual embedded Sherpa revision is793c2405, and the exact source archive has been added; ONNX embedded revisions match the official1.28.1/1.28.2 tags. See the [current release report](../../publication/signed-sdks-release-2026-10-14.md). Older unsigned/candidate status below describes the preceding verification. Independently reproducing every binary is not treated as a blanket publication prerequisite.

The [conversion package model card](https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11#license) explicitly distinguishes MIT sample code from OpenRAIL-M model weights. Both supplied notices remain preserved. The archive MIT file is valid evidence of that notice, but does not supersede the model-specific scope stated by the same package.

## Completed technical work (preceding verification)

- Reverified all614 locked source inputs and the source-derived notices. Built four independently readable TAR parts using an explicit allowlist; reread each member and checked its SHA-256. Unlisted files are excluded. Packaging tests reject corruption, traversal, symlinks and accidental overwrite.
- Published and verified public delivery at [dependency source inputs](https://github.com/etcusr/kat-translator/releases/tag/dependency-sources-2026-10-14), including605 upstream archives, nine Wayu input files, notices, source/submodule/patch mappings, rebuild instructions and a Kat source snapshot at `f491064`. This is a source collection, not a new app release or a declaration of complete corresponding-source compliance.
- Added the missing Wayu frontend attribution and full Apache-2.0 license text. The pinned upstream model card explicitly declares Apache-2.0; no separate LICENSE file exists at that revision (404). The original card is retained in the notice. Kat's frontend transformations are identified. Full Supertonic3 OpenRAIL-M, the different MIT notice actually bundled in the sherpa INT8 archive, and CC BY-NC4.0 texts were also added, with model-specific scope, original sources, hashes and conversion attribution. This supplies the license copies but does not replace enforceable model-use terms. The source tree now packages **46 notice documents**; existing IPA50/PKG69 still contain42 and are unchanged.
- Compared extracted iOS Sherpa, iOS ONNX and Mac Sherpa with their pinned original ZIPs: **9/37/5 files match**, no missing/different files. All three archive hashes match the current official GitHub release asset digests. [Machine-readable evidence](sdk-provenance.json). This establishes artifact origin and local integrity, not a source rebuild or a supplier signature.
- Independently rebuilt Kat's own OpusRuntime from the source kit for iPhone arm64, simulator arm64 and Mac arm64. CTranslate2 patch application and reverse dry-run were checked. The initial exploratory `git apply` inside an ignored subdirectory silently skipped files; that output was rejected. The checked recipe uses `patch` and a reverse check. [Build inputs/toolchain/commands](opus-source-build-inputs.json).
- Added the three privacy manifests and signed the new Opus XCFramework with the application's Apple Development identity and timestamp. Strict/deep signature verification passed. Apple [supports Apple Development or Distribution identities for XCFramework signing](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle). This is Kat's own rebuilt SDK, not a claimed upstream signature. Mac real RU→EN translation passed, as did cancellation during a long translation (return2 in0.066s).

The signed candidate is local at `.build/sdk-provenance-2026-10-14/verified/OpusRuntime.xcframework`. It has not replaced `Dependencies/build/opus/OpusRuntime.xcframework`, the installed apps or the existing store exports. Integrating and testing that exact candidate in the next iOS/Mac release remains necessary; independent rebuild does not claim byte identity with the old SDK.

## Reproduce

```sh
python3 scripts/collect-dependency-sources.py --check
python3 scripts/package-dependency-sources.py --output /path/to/new-publication-directory
python3 scripts/rebuild-opus-source-kit.py --output /path/to/new-opus-build \
  --sign-identity 'your Apple Development or Apple Distribution identity'
```

Use a new output directory. The rebuild consumes only checked source archives, applies the checked Kat patch, invokes the installed Apple toolchain and never downloads code or changes the existing vendor/SDK tree. Omitting `--sign-identity` intentionally produces an unsigned candidate. The source kit must first be extracted into `dist/licensing/dependency-sources-2026-10-14/`; source filenames match the lock. Native build scripts execute upstream build logic; archive packaging does not.

## What remains unresolved

| Item | Exact remaining evidence/action |
|---|---|
| Third-party SDK signatures | Closed for the Kat distribution: three timestamped package signatures pass strict verification and all51 original payload files are unchanged. No upstream supplier signature is claimed. [Current source mapping and release](../../publication/signed-sdks-release-2026-10-14.md). |
| Full binary/source correspondence | Sherpa and its embedded ONNX now have checked release-commit/source mappings. Independent rebuild/link-map verification of transitive inputs, Python support and native Python wheels is not complete. Versions, release hashes, Cargo locks and source availability narrow the uncertainty; they do not remove it. Upstream recipe eSpeak revision is `ed530aa113046142eb5115cf2fc9157854d0ffe1`; the older inventory revision is not claimed as binary correspondence. |
| GPL and App Store delivery | Check the actual accepted Apple agreement and applicable EULA/delivery restrictions against GPLv3§§6/10. A source download is necessary evidence, not an exception granted by eSpeak's authors. No legal compatibility finding or third-party relicensing is claimed. Apple's [agreement index](https://developer.apple.com/support/terms/) states that the accepted English account agreement controls. |
| Supertonic3 | **License mismatch:** the downloaded sherpa INT8 archive carries MIT (Supertone2025), whereas the official model repository carries OpenRAIL-M. Both originals are retained; no upstream weight relicensing is inferred. Clarify the conversion package license scope. Its [OpenRAIL-M§4(a,b),§5](https://huggingface.co/Supertone/supertonic-3/blob/main/LICENSE) requires downstream notice/license delivery and enforceable use restrictions. The current model information link alone does not establish this. Add applicable model-specific user terms and their presentation/acceptance, keeping them separate from Kat's GPL software, or choose a differently licensed package. |
| MMS / OmniVoice weights | Preserve CC BY-NC4.0 attribution, transformations and a clear noncommercial restriction for the exact models. Free app installation does not decide whether a user's model use is commercial. Commercial model use needs permission or a different package. This does not restrict commercial use of Kat's GPL code. |
| Piper / Lessac and other voice provenance | Obtain authoritative checkpoint/base permissions for the exact unresolved packages in [Piper inventory](piper-provenance.csv) and [Denis evidence](denis-lessac.md). Voices remain by the owner's decision; neither a source download nor a dataset label proves every checkpoint right. |
| Thai data and voice previews | The Wayu frontend notice is now included. Rights to underlying datasets/voice identities and111 generated/pre-rendered previews remain distinct from the code license. Existing generation scripts show process, but are not permission from every source rightsholder. |
| Bundled media | [30 concrete files with current hashes](media-rights-pending.json) still lack located rights grants:28 LoadingAnimations MP4/JPG files and2 CatWizard files. Obtain evidence or replace them with owned/licensed artwork. No media was silently deleted. `film-drink` also needs age-rating review. |
| Android only | The22 Google SDK coordinates without source JARs are listed in [coverage](android-source-coverage.json). Verify proprietary Google SDK terms and the final AAB separately; no Android SDK is inferred to ship in Apple targets. |

New numbered app packages, final notices/manifests/signatures, App Store processing and TestFlight are the next release stage. Separate network/radio-off/background acceptance was removed by the owner and is not reported as passed. Cards are reportedly filled; a fresh independent all-language Preview check has not been performed.

## Delivery and validation result

All nine release assets match local sizes and GitHub SHA-256 digests. The public release page returned200 without authentication; anonymous GET and hashes were checked for README, SHA256SUMS, the input manifest and metadata archive. Anonymous HEAD/size checks passed for the four large source parts and Kat snapshot. [Final public URLs and checksums](source-publication.json). Large parts were not downloaded twice; every member had already been read back locally and each server digest matched. The metadata archive records the pre-publication preparation state; this live-verification record is subsequent.

All614 source hashes and source-notice checks pass;18 packaging/license/privacy/documentation regressions pass. The new46-document assembled resource matches every pinned notice. Fresh app exports and final packaged46-document checks are deferred with the next release, as requested. Local commits were not pushed to main; only the explicitly requested source-input publication was made.
