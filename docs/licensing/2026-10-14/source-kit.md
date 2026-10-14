# Dependency source kit — 14 October 2026

The local kit contains **605 complete upstream archives and 9 pinned Wayu source files**, 2,709,554,635 bytes (2.52 GiB). Location: `dist/licensing/dependency-sources-2026-10-14/`. Large source archives stay outside Git. The checked-in [lock](dependency-sources.json) records exact HTTPS URLs, sizes and SHA-256; it allows the same files to be fetched again. Nothing was uploaded or published by this task.

This closes source acquisition for the enumerated inputs. It does **not** certify complete corresponding source for every release binary: a source archive, source JAR or matching version label alone does not establish its complete build inputs, flags or binary provenance.

## Collected and checked

| Area | Evidence and result |
|---|---|
| Local native code | Pinned CTranslate2, whisper.cpp, llama.cpp, SentencePiece, FluidAudio, OmniVoice and initialized/uninitialized Git submodules. [Submodule mount paths](source-submodules.json) include recursive dependencies. |
| Kat patches | CTranslate2 cancellation/deployment patch, OmniVoice cancellation patch and FluidAudio package patch. All three apply cleanly to their downloaded original archives. [Patch hashes and build recipes](source-patches.json). |
| sherpa / eSpeak / Piper | Full sherpa source at `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf`, source archives selected by its CMake recipe, including eSpeak, piper-phonemize, OpenFst, Kaldi decoder/fbank and simple-sentencepiece. Upstream CI/build scripts are retained inside the source archive. |
| eSpeak revision correction | This sherpa recipe uses `ed530aa113046142eb5115cf2fc9157854d0ffe1`; the earlier notice inventory referenced `7251208ee427ef87e94f39d0e99b15d287224ed6`. Both sources are retained and current recipe notices added. The earlier revision must not be presented as proven correspondence to the shipped binary. |
| ONNX Runtime | Full 1.28.1, 1.28.2 and 1.30.0 source archives, Git submodules and source dependencies from their `cmake/deps.txt`. All fetched deps.txt archives match upstream SHA-1 and are additionally pinned by SHA-256. [Dependency map](onnx-deps-map.json). Optional providers/build/test inputs are included; this does not mean all providers ship. Precompiled protoc packages are omitted; protobuf source is included. |
| Python runtimes | CPython 3.13.14 (Apple support b14), 3.14.8 (Android), 3.11.16 (current Mac), Apple support recipe/patches, exact native-dependency recipe tags for Apple and Android, bzip2/libffi/mpdecimal/xz/SQLite/OpenSSL sources. The Apple recipe identifies bzip2 1.0.8, libffi 3.4.7, mpdecimal 4.0.0 and xz 5.6.4. CPython source includes its bundled Expat source and notices. |
| Android crypto | CPython 3.14.8's Android recipe identifies OpenSSL 3.5.9. Its source and notice are included. Apple store packages omit OpenSSL; this does not imply Android does. |
| Mac Python packages | Available exact-version PyPI sdists (verified with PyPI SHA-256), MLX source (no sdist published), pinned mlx-lm and oMLX source, PyTorch source plus recursive submodules. PyTorch tag 2.14.1 resolves to `5c4886908584029761b579af026dcfb627c84070`, matching the packaged `torch/version.py`. Excluded hf-xet is not counted as a shipped Mac store runtime. |
| Rust tokenizers | All **249 registry archives** in the union of the two Python-binding Cargo.lock files, each checked against its Cargo checksum. Every non-root component in the 0.23.3 wheel SBOM is present; the root Rust crate 0.23.2 is inside tokenizers 0.23.3's source tree. Four upstream snapshots supplement license provenance. This lock union includes optional/build/test/non-Apple targets; it is not a claim that all 249 crates are linked. |
| Wayu | Exact TLTK/PyThaiNLP/Misaki/tzdata source distributions and all 9 non-model frontend/config/dictionary input files from the existing lock. Their original hashes match. Kat's transformations remain in `scripts/prepare-wayu.py`. Source availability does not by itself settle every dictionary/dataset permission. |
| Android Maven | **128 source JARs**, 3 metadata-only modules and 22 Google SDK coordinates without a published source JAR at the checked endpoint. [Per-coordinate results](android-source-coverage.json). Parent POM inheritance resolves the missing Commons/Guava metadata; javax.inject is identified by its source copyright/license header. All 153 coordinates now have recorded license metadata/evidence. Proprietary SDK terms remain distinct from source availability. |

## Notices

The shared manifest grows from 38 to **42 documents**, adding four reproducible aggregates:

- Rust: 503 original notice members, deduplicated to 94 distinct texts while retaining every component/path attribution. r-efi uses its `AUTHORS` license text; defmt-parser and wasip2 use their pinned upstream repository licenses.
- Android sources: 6,589 original license files or complete initial source-license comments, deduplicated to 344 texts.
- Native/Python: 370 original notice members, deduplicated to 236 texts, including Python's embedded Expat and the relevant native libraries. Optional/build-only source notices are explicitly identified as a superset.
- Android binaries: 57 embedded AAR/JAR notice members, 8 distinct texts, with archive/member hashes in [the provenance inventory](android-binary-notices.json).

[Source member hashes and selections](source-notices.json) reproduce the first three aggregates without extracting or executing upstream code. Complete comment boundaries and full member hashes are checked. Original text is preserved apart from explicitly recorded decoding and line-ending normalization; identical bodies are shared, not discarded. The fourth aggregate retains original binary notice payloads already present in the resolved cache.

The final app resource is `assets/bundled/ThirdPartyNotices.txt`. Existing signed IPA47 and PKG66 remain unchanged and contain the old notice set. Fresh store artifacts are required.

## Reproduce locally

```sh
python3 scripts/collect-dependency-sources.py
python3 scripts/collect-dependency-sources.py --check
python3 scripts/assemble-source-notices.py --check
python3 scripts/assemble-ios-notices.py --check
```

`--check` on the collector uses no network. Downloads use temporary files and replace a destination only after a correct hash; a failed download preserves the previous file. Archives are never executed by these tools. `source-submodules.json` identifies where each separate Git submodule archive belongs in its parent tree. `source-patches.json` identifies Kat's modifications; upstream build scripts remain in their archives. A source snapshot of Kat at this task's final local commit is stored beside the dependency kit, without `.git`, ignored files, credentials or local chat journals.

## Still open — precise limits

1. **Release binary correspondence and rebuild.** Rebuild the precompiled sherpa/eSpeak/Piper and Python/native runtimes from these inputs with the intended target/toolchain/features, then audit the actual exported app. The download lock and upstream recipes are now local; an independent clean rebuild and complete link map were not performed. This also applies to native code inside Python wheels and any additional FetchContent/build-time inputs beyond the enumerated files. Do not call this kit a fully verified GPL corresponding-source delivery yet.
2. **Source delivery.** Publish/host the verified kit and provide the applicable recipient access mechanism alongside a release. A local ignored directory is not public delivery. No source hosting/upload was performed.
3. **Google proprietary Android SDKs.** Source JAR 404 is not permission to omit SDK terms, nor evidence of a GPL violation. Verify current Google Play services/ML Kit terms and the exact final AAB. The 22 coordinates are explicit in the coverage JSON; no proprietary source was invented.
4. **Distribution terms and assets.** GPL/App Store terms, downstream OpenRAIL/NC conditions, model/voice/dictionary provenance, 111 voice previews and rights for 30 media files remain as in the [release package review](release-package-review.md). Voices and media were not silently removed.
5. **Final packages.** Produce and verify new IPA/PKG/AAB after the outstanding release decisions. Successful local builds below do not replace App Review or device/TestFlight acceptance.

## Validation

All 614 source inputs pass SHA-256 verification; all 249 Rust crate hashes and all ONNX deps.txt hashes match upstream locks. Three native patches apply cleanly. Collector tests cover corrupted downloads, preservation of existing files, offline checking, traversal and symlinks. Notice assembly tests and package-resource tests pass. Fresh unsigned iOS Release, Mac Release and Android debug builds all pass. Their packaged notice bytes match SHA-256 `1c57c983384507806fd75d77057a75865da4ea65d6fb032bf3878c77018f1cae`. Logs are retained locally under `.build/source-kit-review/`. This task does not retest translation quality or install applications on devices.
