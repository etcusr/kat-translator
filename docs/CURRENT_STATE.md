# Kat translator — current state

**English** | [Русский](CURRENT_STATE.ru.md)

The corrected Mac app is now installed at `/Applications/Kat translator.app`: development **0.6.7 (60)**, source fingerprint `mac-c075be03543c17ac`. Four fresh runtime tests passed, including real MLX/Irina and player controls; signature/dependency checks and normal launch passed. Saved DMG/ZIP and App Store70 are unchanged and predate these fixes. [Installation evidence](benchmarks/mac-speech-install-2026-10-17/README.md).

The additional iPhone Index 9B comparison is complete: MTP with two draft tokens remains unchanged. MTP off, one/three draft tokens and Q8 KV cache showed no demonstrated repeatable improvement over the final control; all six translations matched. More compressed weights and an iPhone MLX port remain proposals. [Recorded comparison and limits](benchmarks/ios-mt-options-2026-10-17/README.md).

The corrected Apple speech build is now installed on iPhone 17 Pro as development **1.0 (52)**. Two fresh device scenarios passed: long sentences/whitespace/ordinals and real Index 9B → Irina. All nine playback buffers completed through the real phone player, with each word synthesized once; independent recognition of both generated waveforms retained the full word sequence. Preferences were unchanged; temporary fixtures were removed and the app reopened normally. No store upload. [Device evidence and limits](benchmarks/iphone-speech-correctness-2026-10-17/README.md).

Apple streamed speech now retains all synthesis fragments and exact newline/space boundaries, fixing truncated or repeated sentences. Russian ordinal expansion uses grammatical context; default Mac Index 9B/MLX now supplies partial translations. Fresh Mac checks passed with real MLX and Irina, including early playback and each word once; independent recognition also retained the complete control audio. OfflineCore: 288 tests, 2 opt-in skips, no failures; MLX bridge: 9 tests; real Mac integration: 3 tests. Mac and unsigned iOS Release builds passed. That initial Mac check did not replace the normal app or install on iPhone; the later iPhone installation is recorded above. [Correctness checks and limits](benchmarks/apple-speech-correctness-2026-10-17/README.md).

Android now offers optional **Whisper large-v3-turbo Q8** (874 MB). On the same 25.18-second recording, fresh app recognition took **14.36 s versus 26.03 s with F16 (1.81× faster)**. Words, numbers and time match; only quotation marks differ. Q8 is installed and explicitly selected on Pixel; F16 and Auto routes remain available. Isolated development APK: 108 unit tests, lint and five device tests passed; version unchanged. One-recording quality evidence only. [Variant comparison and limits](android/benchmarks/2026-10-17-whisper-options/README.md).

iPhone/Mac now start speaking each finished sentence of the translation while the rest is still generated; the translated text is unchanged. In the earlier measurement, before the correctness fixes above, on iPhone 17 Pro a 5-sentence phrase started speaking **3.1 s instead of 7.1 s** after recording stopped. Piper uses up to four threads, processing during recording is on by default, the default Russian voice is Irina on all platforms (an installed Denis is kept until Irina is downloaded) and Russian ordinals such as "16-е" are spelled out before speech on Apple. Development build only; no version change. [Measurements and limits](benchmarks/ios-speed-2026-10-17/README.md).

Android Whisper large-v3-turbo F16 now uses FP16/dotprod CPU instructions where supported, with a baseline arm64 fallback. On the same 25.18-second recording, the real app recognition stage fell from **117.41 to 37.67 s (3.12× faster)** with identical text. The model and decoding settings are unchanged; the Pixel warmed into throttling, so this is an observed comparison rather than a universal speed claim. Builds, 107 unit tests, lint and 12 device checks passed. The updated development APK is installed without a version change. [Measurements and limits](android/benchmarks/2026-10-17-whisper-latency/README.md).

Android VITS/Piper synthesis now uses up to four CPU threads with unchanged voice weights and quality settings. On Pixel, the same 257-character input took **10.42 s versus 17.38 s** in the synthesis stage (40% less); generation dominated the original wait. App/test builds, 107 unit tests, lint and four functional device checks passed. The updated development APK is installed with version unchanged. [Measurements and limits](android/benchmarks/2026-10-17-tts-latency/README.md).

Android voice mode now shows both original and translation cards immediately and keeps the original expanded. The active playback button becomes a stop cross and returns to a speaker after stopping or completion, including automatic speech. The rebuilt development APK is installed on Pixel (version unchanged: 0.4.6 / code 21); 107 unit tests, lint and 4 device checks passed. Settings/history were preserved. [Checks and limits](android/benchmarks/2026-10-17-voice-results/README.md).

Android media builds now include the existing inference-privacy helper required by the shared speech runtime, fixing an unresolved-symbol link failure. App and instrumented-test APK builds passed. [Build check](android/benchmarks/2026-10-17-media-link/README.md).

iOS **1.0 (52)** was verified and uploaded to App Store Connect on 17 October. It includes the microphone and memory-pressure fixes, tap recording defaults and 13 loading clips. TestFlight installation and acceptance are pending; the owner will replace the current review build and resubmit. [Release verification](publication/ios-store-build52-2026-10-17.md).

The iPhone startup now disables persistent ggml Metal residency while keeping models loaded. This addresses the captured CoreAudio `mlock` failure behind microphone error 1852797029 with Index 9B; memory saving stays off. A local development 1.0 (51) was built and checked on the phone. These fixes are now included in the uploaded build 52; its TestFlight acceptance is tracked above. [Cause, checks and limits](publication/ios-microphone-wired-memory-2026-10-17.md).

When iOS reports memory pressure with a large translator and a loaded recognizer, the pipeline now releases the recognizer at a safe boundary instead of cancelling the turn and unloading Index. Translation readiness, the result and speech playback are preserved; recognition reloads on the next capture. The saved memory-saving preference is unchanged. Full acoustic-cycle verification is recorded in the same report.

The microphone defaults to tap to start / tap to stop on iOS, macOS and Android. A saved recording-mode choice is preserved; hold to record remains available in Settings. The iOS change is included in build52; other installed platforms need a new build.

One loading clip has been removed from the shared iOS/macOS/Android resources, playlist, preparation script and gallery. The source catalog now contains 13 clips. Uploaded iOS52 contains the current 13 clips. Mac70 still contains the removed clip; its replacement remains deferred. [Verification](publication/loading-clip-removal-2026-10-14.md).

Working tree reconciled on **14 October 2026, Europe/Moscow**. After fixing seven Auto/OPUS regressions, local Android/OfflineCore tests, Mac runtime/UI tests and an iOS build were run. Details and limits: [fix report](benchmarks/auto-routing-fixes-2026-10-13/README.md). After the backup finished, **iPhone build 45 and Pixel code 21 were installed and verified**: [phone tests](benchmarks/auto-routing-devices-2026-10-13/README.md). Then real ASR→Auto MT→TTS and the microphones of both phones were checked: [voice run](benchmarks/voice-auto-devices-2026-10-13/README.md). Routing passed; a single iPhone audio output error and an extra Whisper word in one recording remain observations with an unknown cause.

## Signed SDKs and the new release (14.10)

Three third-party XCFrameworks are signed as Kat distributions; 51 source files before/after signing matched the official ZIPs. Based on embedded identifiers, the Sherpa reference was corrected to 793c2405; ONNX iOS 1.28.1 and the bundled Mac 1.28.2 matched their release commits. The correct Sherpa archive was added to the kit (615 inputs). This is a provenance and version check, not a claim of byte-for-byte reproducibility. New iOS 51 / Mac 70 were built, verified and uploaded to App Store Connect with the playback fix and 46 notices. 138 tests PASS; signatures of 72/154 Mach-O files verified. The first iOS upload was rejected because two libraries lacked MinimumOSVersion; packaging was fixed and the re-upload succeeded. Processing/selecting the builds and App Review remain with the owner. [Verification](publication/signed-sdks-release-2026-10-14.md).

## Previous SDK and source kit check (14.10)

614 source inputs were re-checked. Archives, metadata and a code snapshot are [published](https://github.com/etcusr/kat-translator/releases/tag/dependency-sources-2026-10-14); 9 files were compared with server hashes and access without authorization was checked. Our own Opus runtime was built from scratch for 3 platforms from the kit and signed as an SDK with manifests; a real Mac translation and cancellation PASS. iOS/Mac Sherpa and iOS ONNX matched the upstream ZIPs and release hashes but remain without a vendor signature. Wayu/OpenRAIL/CC BY-NC were added: 46 notices in the sources, 42 in the unchanged IPA 50 / PKG 69. [Result and specific limits](licensing/2026-10-14/publication-and-sdk.md). The new Opus was then a separate candidate; integration and device acceptance were planned for the next build.

## iPhone playback fix (14.10)

Fixed the reproducible deactivation of the shared audio session by idle player/recorder objects and waiting on interrupted playback. Two tests failed before the fix; afterwards 6 PASS on iPhone plus 2 PASS on repetition, Mac player 1 PASS, OfflineCore 270 PASS / 2 opt-in skips. [Cause, checks and limits](publication/ios-playback-fix-2026-10-14.md). Store IPA 50 / PKG 69 were not changed and needed the next build. A separate network/radio-off/background download check was dropped by the owner's decision; store listings were filled in according to the owner's message, without an independent Preview check. Next stage: SDKs/licenses/public sources, then new packages and TestFlight.

## Working directory cleanup (14.10)

After a double check, outdated iOS migration copies, compile caches and three reproducible PKG extractions were removed. The project shrank from 156.9 to 80.5 GiB; models, sources, SDKs/environments, all finished releases and the license kit were kept. Metadata of 565 598 files/links and SHA-256 of 912 files were verified. There are no migration copies for a local rollback anymore; devices were not changed. [Result and check limits](maintenance/cleanup-2026-10-14.md).

## Interface languages (14.10)

Spanish and Turkish were added to the iOS, macOS and Android sources. RU/EN/ES/TR and the system language option are available; if no preferred language is supported, English is used. A separate Montenegrin localization was not added. The interface language does not change the selected translation languages or models.

Catalogs, substitutions and plural forms were checked; iOS/macOS builds and Android/OfflineCore unit tests passed. Later the main ES/TR screens were checked on iPhone 1.0 (47); review by native speakers and a full pass of permissions/accessibility remain. The localization run itself did not replace installed apps. Later the localized iPhone build 46 was installed during the migration acceptance; Mac/Android were not updated by that migration. [Report](benchmarks/localization-2026-10-14/README.md).

App Store copy for iOS/Mac is prepared in all four languages: [72 fields and review notes](publication/2026-10-14/LOCALIZATIONS.md). 32 new screenshots are ready: 16 each for [iPhone 1.0 (49)](publication/localized-screenshots-2026-10-14.md) and the [verification Mac 0.6.7 (60)](publication/localized-macos-screenshots-2026-10-14.md), four per RU/EN/ES/TR. Both UI scenarios passed, the original history was preserved and settings restored. The Mac capture is not an acceptance of the store PKG 68. The upload package is collected by `scripts/publication/build-apple-store-package.py` into local `dist/store/apple/`: one plain-text `APP-STORE-TEXTS.txt` with every field grouped by App Store Connect section and language, numbered screenshots per platform/language, Header/Search Results. Sources are in `dist/store/_sources/`, superseded sets in `dist/store/_archive/`.

## License and publication preparation (14.10)

**Previously saved store packages: iOS 1.0 (50) and Mac 1.0 (69).** The current 51/70 are described above; the following refers to the earlier run. They contain the current app manifests for third-party downloads: nine declarations each and 42 license documents. The final IPA/PKG were checked: signatures of 72/154 Mach-O files, distribution profiles, Mac sandbox/helpers, no OpenSSL/rustls/BoringSSL or XCTest found. All 132 Python tests passed. Those packages were not uploaded or installed; the earlier 49/68 are kept. [Fresh check and hashes](publication/hosting-manifests-release-2026-10-14.md). App Privacy was published by the owner and confirmed by a screenshot of App Store Connect; the RU/EN policy is published separately.

Earlier [runtime check 50/69](publication/runtime-acceptance-2026-10-14.md): iPhone downloads/preview/Wayu passed, but two voice scenarios first failed on audio output 1852797029, and one separate Thai run hung. The last Auto and RU→TH repeats passed; the cause was not established, so voice acceptance remains open. The ordinary development 50 without XCTest was installed; 40 settings and the history were preserved, 8 604 model/document files kept their paths/sizes; 10 verification receipts were refreshed. Isolated Mac 69: 4 runtime + 2 Thai/network control + 5 offline tests PASS; the offline copy has no network-client entitlement and the control request is blocked. Temporary Mac data were removed. There is no full iPhone network trace and no acceptance of the distribution packages/TestFlight.

**605 source archives and 9 frontend files** (2.52 GiB) were collected, including pinned submodules, sherpa/eSpeak/Piper, Python/native, ONNX deps.txt, 249 Rust crates and 128 Android source JARs. Notices were expanded to **42 documents**; fresh verification builds for iOS/Mac/Android and the packaged resource match passed. This was the initial collection; the sections above/below describe the public delivery, 46 notices and the signed clean-rebuilt Opus. Correspondence of the other prebuilt binaries remains a separate task. [Contents, reproduction and remaining work](licensing/2026-10-14/source-kit.md).

Kat's own code is distributed under **GPL-3.0-or-later**. [Terms](LICENSING.md) · [history review](maintenance/public-source-audit-2026-10-14.md) · [staged publication queue](publication/OPEN_QUESTIONS.md). eSpeak stays; the separate VoiceGarden prototype was cancelled until a quality assessment is complete and was not added to the product. **Denis and all other current voices remain in the catalog.** No explicit prohibition was found; the rights uncertainty is not hidden. [23 Piper packages checked and alternatives found](licensing/2026-10-14/voice-alternatives.md). [Rights confirmations](licensing/2026-10-14/denis-lessac.md).

iOS 0.5.16 / build 46 with a privacy manifest and the new ID was installed separately; models, history and settings were migrated. File checksums and Auto voice scenarios were verified. The ordinary clean build was installed and launched; the old app was kept. [Migration result](maintenance/ios-kat-migration-2026-10-14.md). The App Store Connect record exists for iOS/macOS; the current uploaded builds iOS 1.0 (51) and Mac 1.0 (70) are described above. Unused `_ssl`/`_hashlib` with OpenSSL were removed from the iOS package; downloads via URLSession, file verification via CryptoKit and the local Wayu are kept. In the historical OpenSSL-removal check, separate privacy manifests were installed for Python, TranslationRuntime and OmniVoiceRuntime; that Release archive and App Store IPA contained four declarations together with the app's and passed the strict signature check. The current IPA 50 has nine declarations, as described above. 72 binary files were checked without OpenSSL markers found; 31 targeted tests passed, OfflineCore 272 tests with two regular skips and no failures. [Checks and limits](publication/ios-openssl-removal-2026-10-14.md). Then the build without OpenSSL was checked on iPhone: 5 integration tests for downloads/Auto/Thai Wayu and a repeat of downloads after fixing the test cleanup passed. The ordinary build was installed and launched; settings, history and model paths/sizes were preserved. [Device acceptance and limits](publication/ios-openssl-device-2026-10-14.md). In that historical run the store IPA in dist was not replaced; the new 1.0 (47) package is described below. App Privacy is now published; Apple's processing of the new package remains.

The iOS `Info.plist` has the Boolean `ITSAppUsesNonExemptEncryption = NO`: after removing OpenSSL the app uses the OS encryption for HTTPS. This is a declaration of exemption from additional documents, not a statement that HTTPS is absent. [Setting and build check](publication/ios-export-compliance-2026-10-14.md). The key was also verified in the installed 1.0 (47); the Mac App Store build carries the same key (see the Mac report).

In `cat-break`, both Russian captions were replaced with **CAT BREAK** for all iOS/macOS/Android languages; the MP4, poster and gallery were updated. [Resource preparation](branding/loading-animations/README.md).

The shared animation set was reduced to 14: `one-beer` was removed from iOS/macOS/Android, resources, the generator and the gallery. Old signed packages were not changed. The Mac 64 archive confirmed all 14 current clips, no one-beer and the English cat-break. After updating the expectations, four Mac animation tests passed; the full runtime test suite is not closed by this.

The [license kit of the final packages](licensing/2026-10-14/release-package-review.md) was checked: 38 source texts, offline viewing in the Apple apps and a shared file on Android. Fresh iOS/Mac/Android builds and the resource byte check passed; IPA 47 / PKG 66 are kept as earlier packages; the current notices were included and checked in IPA 49 / PKG 68. Completeness of transitive sources/notices, GPL/App Store terms, OpenRAIL/NC and media rights are not closed.

## Mac App Store (14.10)

Mac build **1.0 (64) was rejected during Apple's server processing**: ITMS-90284 for `FluidAudio_FluidAudio.bundle` and `OfflineCore_OfflineCore.bundle`. A successful upload and a local signature check did not mean acceptance. In the exported PKG 65 the absence of separate signatures on those resources, the strict app signature and the certificate/profile match were verified; at the time of that check Apple had not confirmed acceptance yet. In 65 the resource bundles still carried the app's Info.plist and bundle ID (global build overrides); **1.0 (66)** was built from a separate store project with settings only on the app target, verified locally, uploaded and **accepted by Apple: 65 and 66 — Complete / Ready to Submit** (ASC screenshot 14.10); 66 was selected for version 1.0; then 1.0 (70) was uploaded (see "Signed SDKs" above), and its processing and selection in the Build field are up to the owner. [Build report](publication/macos-appstore-build-2026-10-14.md) · [independent review and open remarks](publication/macos-release-verification-2026-10-14.md).

64 kept `app.kattranslator`, App Sandbox, no OpenSSL/rustls and `ITSAppUsesNonExemptEncryption = NO`; OPUS GPU was fixed by keeping the sandboxed helper. According to the report, Index 9B/2B, OPUS GPU/CT2, Auto, Parakeet ASR, Piper TTS, Wayu, OCR and downloads passed inside the test sandbox. In a later direct Release run after fixing the test infrastructure: 58 tests, 51 PASS, 7 opt-in skips, 0 failures. Archive error handling, verifiable container cleanup, fixture/result paths and an outdated model choice in the tests were fixed; [fresh check and its limits](publication/release-check-fixes-2026-10-14.md). This is not a repeat of the sandbox/TestFlight acceptance. The live microphone, screen capture, hotkeys/Accessibility, file panels and the first launch in TestFlight were not checked. The direct build 0.6.7/60 was not replaced. [Run report](publication/macos-appstore-build-2026-10-14.md).

[Four real iPhone screenshots 1206×2622 and the Russian listing](publication/ios-store-screenshots-2026-10-14.md) were prepared. The final UI scenario passed; settings and history were preserved. The first set refers to build 46. New screenshots for 1.0 (47), ES/TR listing material, the archive and the license kit were also prepared: [fresh check and open questions](publication/ios-release-preflight-2026-10-14.md).

Separate [Header 3840×1646 and Search Results 3840×2560](publication/2026-10-14/creative-assets/README.md) images were prepared: PNG, sRGB, no transparency. They were updated with a black background and an outlined cat in the style of the loading animation; copies for iOS 47 / Mac 66 were placed in their directories. Sizes and files were checked; upload to App Store Connect and Preview were not done at that point.

## Privacy policy and hosting (14.10)

The [RU/EN privacy policy](https://etcusr.github.io/kat-translator/privacy/) is published, contact **katlabs.dev@gmail.com**; [source and check limits](publication/privacy-audit-2026-10-14.md). The [repository](https://github.com/etcusr/kat-translator) is public and started from a new initial commit without the previous history. The GitHub Pages deployment succeeded; the home page and the policy are available without authorization (HTTP 200); the updated policy text about downloads was published from de5f079: the deployment succeeded and the public HTML matches the source byte for byte. The checked old commits are not available in the new repository. No automatic transfer of translation content to the developer was found in the checked Apple paths. For third-party downloads, the App Privacy answer **Yes** with a conservative disclosure was prepared: Coarse Location, Device ID (IP / IP hash), Product Interaction and Other Diagnostic Data; linked — Yes, tracking — No. This is processing by the hosting services, not the developer receiving texts or logs. The RU/EN policy is published, app manifests are updated in the sources; App Privacy was published according to the App Store Connect screenshot of 14.10, the new packages 50/69 were built and verified, final acceptance remains. [Rationale, purpose table and limits](publication/model-download-privacy-2026-10-14.md). [Fresh SDK review and limits](publication/apple-privacy-sdk-2026-10-14.md). Voluntary sending and technical metrics of third-party services are described separately. Android ML Kit sends technical metrics to Google. With audio saving enabled, both platforms also save the original speech; an incorrect settings text was fixed. This was a text change, not a change of processing or SDKs.

Third-party model sources are used without our own hosting at this stage: 10 OPUS packages are downloadable, 44 require manual installation. Descriptions do not promise that all 54 are downloadable. The iPhone 46 migration was checked separately in the device report.

## iPhone signing and the new ID (14.10)

In the sources the main bundle ID is **`app.kattranslator`** and the extension is **`app.kattranslator.downloads`**. The development candidate 0.5.15 / build 45 with the new ID was signed successfully through Xcode; the strict signature check and 98 validation tests passed. The app profile is valid until 14.10.2027 (Europe/Moscow), increased-memory-limit is kept; the extension was signed with a wildcard development profile at that time. [Details and next step](maintenance/apple-signing-2026-10-14.md).

The build 45 signing candidate is kept separately in `dist/ios/signing-candidates/`; it was not installed. Instead, the new `app.kattranslator` app was installed as build 46 with data migration. The old `org.openoffline.translator.prototype` is kept. The App Store Connect record was created for iOS/macOS; no TestFlight upload had been done at that time. Mac/Android IDs did not change in that step.

## Releases

| Platform | Version | Build requirement | Confirmation |
|---|---|---|---|
| Android | **0.4.6 / code21**, Debug | API 31+, arm64-v8a (ARMv8.2 dotprod/FP16 for Index); compile/target 36 | Installed on Pixel 9 Pro 13.10; native Auto OPUS→2B→OPUS, EN→EN, manual RU↔DE; voice RU/DE via import/microphone with GigaAM/Parakeet and TTS verified |
| iPhone | **1.0 / build52** | iOS 18+, iPhone ARM64 | IPA52 verified and uploaded: 9 manifests, 46 notices, 72 signatures, 70 framework deployment checks. TestFlight acceptance pending. [Report](publication/ios-store-build52-2026-10-17.md) |
| Mac modern | **0.6.7 / build60** | macOS 27+, Apple Silicon | Installed corrected development build: `mac-c075be03543c17ac`; saved DMG/ZIP are older |
| Mac App Store | **1.0 / build70** | macOS 27+, Apple Silicon, sandbox | PKG 70 verified and uploaded: 9 manifests, 46 notices, 154 signatures and sandbox/helpers. Apple started processing; build selection by the owner. [Report](publication/signed-sdks-release-2026-10-14.md) |
| Mac compatible | **0.6.0 / build53 / macos15-26** | binary minimum macOS 15, Apple Silicon | Saved DMG/ZIP and audit; launch verified on macOS 27, physical macOS 15–26 not tested |

Android code21 with the later Whisper Q8 option is installed on Pixel. The Mac application was replaced on 17 October with the current corrected sources. The older saved build60 DMG/ZIP still predate those fixes; use the source fingerprint above to distinguish the installed executable.

Artifacts (13.10):
- `dist/android/kat-translator-0.4.6-debug.apk` (SHA-256 `1f0937878c09c2d0920db61f025ccd786ea6cc040496853ced00e89ba28cf70e`); 0.4.5, 0.4.4 and 0.4.3 are kept as well;
- `dist/macos/Kat-translator-0.6.7-build60-mac-arm64.{dmg,zip}` (DMG SHA-256 `28224f25b29e9f5bcc759dbc7d5c7a660d1f281f663a3d86fa2b6b8e93478a41`), plus 0.6.6 and 0.6.5 and the compatible `0.6.0-build53-macos15-26`;
- `dist/ios/Kat-translator-0.5.15-build45.app` — a copy of the build installed on 13.10; the 14.10 check found broken signatures of nested Python frameworks, so do not use it for reinstalling without restoring them; 0.5.14, 0.5.6 and 0.5.5 are kept too (iOS 0.5.7–0.5.13 were not saved in `dist`).

Android checksums are in `dist/android/SHA256SUMS`; Mac checksums in the `*-SHA256SUMS.txt` files next to the DMG/ZIP. The contents of `dist` are local and not part of Git.

There is no store publication: the iOS/Mac builds are uploaded to App Store Connect but not submitted for review. The Android APK is signed with a debug key. The direct Mac build uses the existing Apple Development certificate; there is no Developer ID/notarization. The publication ZIP is preparation material, not a finished store build.

## What is implemented now

### Translation and initial setup

- **"Auto" is the initial translation choice on all three platforms.** A saved manual choice is kept. The device check before choosing languages takes about 3–5 s and measures CPU/Metal or Vulkan GPU without downloading models; the result is a 9B speed estimate, not a translation measurement. Thermal headroom: 0.7 on phones, 1.0 on Mac. Powerful-device threshold: RAM ≥11.5 GB and an estimate of ≥6 tok/s on iPhone, ≥8 on Mac/Android.
- During translation "Auto" chooses among the installed models: powerful device → Index 9B, then 2B; others → OPUS for a supported pair, then 2B and 9B. Apple first checks the legacy EN package, then the separate directions. The model is resolved after the actual language of the text/speech is detected (including preview); the Auto language list is not limited by the current engine. With a manual choice there is no automatic model substitution. Sources: `TranslatorState.resolveModel`, `AutoTranslation.resolve`, `PackageDownloadCoordinator`.
- "Your languages" builds the MT/ASR/TTS plan and the total size. For a powerful device 9B is planned; for others an available OPUS for the selected pairs, otherwise 2B. Android supports several own languages; Apple one own language plus translation languages. Details: [Android Auto](android/benchmarks/2026-10-13-auto-translation/README.md), [Apple](benchmarks/apple-device-check-2026-10-13/README.md).
- **Index 2B is integrated on iPhone, Mac and Android.** The official Q4_K_M, 1 312 164 352 bytes: Metal on Apple, Vulkan on Android. On Mac it is a separate llama.cpp backend, not MLX 9B. On Android MTP is enabled only for 9B. 2B is faster on the tested examples but behind 9B in quality; full language acceptance is not complete.
- **OPUS-MT Big — 54 directions** in the `opus-direction-packages.json` catalog (35 languages). These are model packages: one group package can serve several pairs. The 54 OPUS directions run via CTranslate2 CPU INT8 on all platforms. The legacy EN↔RU/UK/BE package uses a separate PyTorch Metal FP16 worker on modern Mac and CT2 CPU on phones.
- The short coverage label EN ↔ ~30 languages means the union of English partners in both directions, not a promise of both directions for each language. Exact routes are defined by the catalog; PT→EN is missing, EN↔KO and RU→Serbian Latin are excluded. 10 directions are downloadable; the remaining 44 require manual installation until hosting is available. With several routes the first installed one is chosen, so a missing bg-en does not block an installed zls-en. Direct pairs without English are already implemented; there is no hidden pivot. [Directions](android/benchmarks/2026-10-13-opus-directions/README.md).
- The "OPUS directions" menu on all platforms: search, direction selection, status/size, total size and one download button. The Apple button uses the shared network confirmation with the size, including re-allowed cellular downloads. Android setup takes already installed manual directions into account; an Auto switch between OPUS/Index releases the previous context and lease. Identical source/target languages bypass MT. The pair packages from Android 0.3.9 were replaced with direction packages; the old report describes only that stage.

### Android

- Compose: text, voice, camera, history, downloads, playback and sharing of the original/TTS. Index 9B — GGUF Vulkan/MTP, Index 2B — GGUF Vulkan without MTP, OPUS — CT2 CPU INT8. `PackageCatalog.DEFAULT_TRANSLATION_BACKEND="opus"` is a legacy constant; the current initial setting `auto` comes from `TranslatorState`.
- The CPU part of ggml is built for ARMv8.2 dotprod/FP16; `index_jni` checks HWCAP before starting. i8mm is not enabled. This is not an acceleration of the Vulkan path. The Mali-G715 Q6 optimizations are kept; specific measurements refer to [release 0.3.7](android/benchmarks/2026-10-12-mali-q6-kernels/README.md).
- ASR Auto by the explicitly chosen language: Russian → GigaAM v3; the other 24 languages of the 25-language Parakeet catalog → Parakeet TDT v3. A missing required package is offered for download; a manual choice takes priority. The earlier ASR check covers RU/EN; the latest voice run also verified DE/Parakeet, including the microphone. This is not an acceptance of all 25 languages. Other languages keep separate on-device/Whisper/Meta paths; there is no cloud fallback. PCM import into the system service requires Android 13+.
- Voice and camera use an explicit language; "Auto" in the ASR settings chooses an engine, it does not detect an unknown spoken language. After ASR, Auto MT receives the language of the result and chooses an installed model. Text auto-detection remains.
- OCR: bundled ML Kit for supported scripts, Russian PP-OCR with the mobile detector. No Latin OCR substitution for an unknown script.
- Recorded audio for playback/export is normalized with up to 32× gain; the raw PCM for ASR is not changed. Stage timings, model preparation/unloading, history and animations are kept.

[Index 2B checks](android/benchmarks/2026-10-12-index2b-default/README.md) · [Pixel speed audit](android/benchmarks/2026-10-12-pixel-speed-audit/README.md) · [ASR](android/benchmarks/2026-10-12-asr-routing/README.md) · [recording integrity](android/benchmarks/2026-10-12-asr-completeness/README.md) · [UI/audio](android/benchmarks/2026-10-12-parity-034/README.md) · [OCR](android/benchmarks/2026-10-12-hybrid-ocr/README.md). Test counts in those reports refer to the corresponding releases.

### Interface and automated checks (13.10, all platforms)

Result of the overnight fixes; details are in the test reports and the [layout](benchmarks/ui-layout-audit-2026-10-13/README.md) and [Apple](benchmarks/apple-device-check-2026-10-13/README.md) reports.

- **Fonts.**
  - In the Voice tab the original and the translation use the same size (`AppPlatform.voiceTextFont`, iOS 0.5.9).
  - The "Your languages" and "OPUS directions" screens use only shared AppPlatform styles.
  - Android statuses use one size (`Status`).
- **OPUS caption.** "35 languages via OPUS directions · this package: English ↔ Russian, Ukrainian, Belarusian" instead of "4 languages" (all platforms). The intro text of "Models" on iPhone and Mac talks about Index 2B / 9B and OPUS directions, as on Android.
- **OPUS directions menu on iPhone and Mac** (`OpusDirectionsView`; iOS 0.5.10, Mac 0.6.3): search, per-direction checkboxes, total size, one "Download" button. Same as Android 0.4.1.
- **Alignment.**
  - Android: text buttons in cards start at the text edge (`GroupActionPadding`).
  - Apple, "Your languages":
    - toggles are aligned and do not overflow the cards on iPhone;
    - sizes in "Required models" sit at the right edge (`SizeRow`);
    - "Download" and "Done" have the same width;
    - if everything is downloaded, "Download" is disabled and "Done" saves the selection;
    - the bottom bar is opaque and padded.
- **Size units** follow the app language: `L10n.bytes` on Apple, `bytes` on Android. Previously iPhone wrote "ГБ" with the English interface and Android wrote "MB" in Russian.
- **Automated checks.**
  - Static (`scripts/validation`, part of the regular run):
    - `test_ui_typography.py` — shared font for original and translation, only AppPlatform styles on panel screens;
    - `test_docs_app_parity.py` — numbers in the app texts and in `CURRENT_STATE` / `ARCHITECTURE` (English and Russian versions) are compared with the catalogs (OPUS languages and directions, Index, Ultra, Omnilingual and Supertonic languages), and the version table with Gradle and Info.plist.
  - Layout UI tests (without starting model downloads):
    - Android `UiLayoutAuditTest` — "Models", "Your languages", "Settings", units;
    - iOS `testPanelScreensAlignLineStarts` — line starts, button widths, toggle edge by pixels, sizes at the right edge, units, bottom bar; plus `testOpusDirectionsSelectionShowsTotal`;
    - Mac `testLanguageSetupAlignsLineStartsAndActions` — line starts, button widths, sizes at the right edge.
  - According to the 13.10 layout report the checks passed on Pixel, iPhone and Mac; the final repeat after restoring the Xcode account — 3 iOS and 2 Mac UI tests. The layout tests were not repeated in the later Auto/OPUS run. iOS limitation: a shift inside a row is not visible in standard `List`s.

### Mac and iPhone

- Index 9B: Mac — MLX 4-bit + MTP2 (8 files, 5 243 376 219 bytes); iPhone — GGUF/Metal + MTP2. Index 2B and the new OPUS directions run on separate paths described above.
- Legacy Mac OPUS EN package: a separate Python worker, PyTorch Metal FP16, beam 5; GPU package 965 472 092 bytes. Six directions, cancellation/reuse and the Index regression were checked in the Mac 54 report. This does not describe the runtime of the new directions.
- The shared SettingsView saves values immediately; deleting history for changed limits is postponed until settings are closed.
- The compatible **Mac 53 / macos15-26** keeps Index 9B MLX+MTP2 and the earlier OPUS CPU. It does not contain Index 2B, the new directions, translation "Auto" or the later UI changes of the modern release. It uses the same 9B package; the weights do not need to be downloaded again.
- Apple ASR Auto: ordinary Whisper for its languages, Meta Omnilingual for additional ones; Ultra/Core ML is a manual option. The Android GigaAM/Parakeet routing is not ported to Apple.

[Apple 13.10](benchmarks/apple-device-check-2026-10-13/README.md) · [Mac 54 / iOS 36](benchmarks/mac-opus-gpu-release-2026-10-12/README.md) · [Mac Index MLX](benchmarks/mac-mlx-release-2026-10-12/README.md) · [iOS MTP](benchmarks/ios-mtp-release-2026-10-12/README.md) · [macOS 15–26](benchmarks/macos15-26-release-2026-10-12/README.md).

## Research and integration boundaries

- **Index 2B vs 9B (12–13.10)**: the research preceded the 2B integration on all platforms. On the selected articles 2B is 3.5–4.7 times faster but worse in quality; there were also small multilingual probes. This is not a full acceptance of all languages and not a universal speed-up factor. [Device and quality comparison](benchmarks/index2b-cross-device-2026-10-13/README.md), [initial research](android/benchmarks/2026-10-12-index-alternatives/README.md).
- **Compact pairs (13.10)**: Tower+, Hy-MT2, EuroLLM and NLLB are not integrated. The direct OPUS pairs considered in the research were later integrated through the direction catalog. [Historical comparison](benchmarks/compact-pair-models-2026-10-13/README.md).
- **Pixel speed (12.10)**: 9B is limited by memory bandwidth; the CPU path is thermally unstable. Hy-MT2 and TranslateGemma were researched but not integrated; after the 13.10 cleanup their weights were moved to the Trash, like the other non-integrated research models. [Report](android/benchmarks/2026-10-12-pixel-speed-audit/README.md).
- **Android OPUS Vulkan FP16**: the GPU executes the graphs, CPU/GPU greedy parity is confirmed; beam 5 on the tested examples is 2.5–3.8 times slower than CPU. The prototype is not integrated. Do not compare a short greedy beam 1 with the production beam 5. [Report](android/benchmarks/2026-10-12-opus-vulkan/README.md).
- **iPhone OPUS Core ML GPU**: a separate experiment showed a 1.55–2.30× slowdown and new text/HTML insertions in 2 of 4 cases. Not integrated. Results are in the external `kat-translation-lab-2026-10-10`; the path is in the Mac 54 / iOS 36 report; that directory is not part of the export.
- **Index 9B MNN/OpenCL**: the experiment is closed. On the same text on the Pixel: MNN after warm-up 53.2–53.8 s; control Vulkan/MTP 47.5 s, without MTP 50.9 s. No speed-up. Temporary builds and converted weights were removed; the [report](android/benchmarks/2026-10-12-index-mnn-opencl/README.md) is kept.

## Not yet confirmed

1. Physical macOS 15–26; a lower OS deployment target alone does not prove all features.
2. General quality of all ASR/MT/TTS/OCR languages, quality of long conversations, actual suitability of each voice. Model licenses differ; being in the catalog does not mean suitability for any way of publishing.
3. Full Android/iOS functional and visual identity; the full microphone/ticker preview → native path on Android, the whole MMS/language set and real network foreground-service transfers. Compare the older open items of the [matrix](android/FEATURE_PARITY.md) with later reports.
4. A physical Android device with 16 KB pages, weaker devices and minimum RAM for OPUS. Pixel checks were done on a 9 Pro / API 37 / 16 GB / 4 KB pages.
5. Index 2B on Android: in-app network download, full multilingual acceptance against 9B (only spot probes were done), devices without Tensor G4. Devices without ARMv8.2 dotprod/FP16 get a clear Index error instead of a crash — not tested on such a device.
6. Final store/release builds, publisher/contacts, final materials and publication. [Preparation kit](publication/2026-10-12/README.md).

## How to read the history

Priority: current code/catalogs and the version of a specific artifact → the test report of exactly that build → this overview → historical plans/READMEs. Code proves the implementation, not automatically a successful hardware test. `docs/CURRENT_STATE.md` contains accumulated history; new entries may supersede the conclusions of older ones. Test counts refer to a specific run.

## Build retention and disk space

The last three available finished versions of each platform are kept (see "Artifacts" above). On 13.10 the project was cleaned: 88 → 64 GB. Moved to the Trash (`kat-cleanup-2026-10-13`) rather than deleted:
- temporary builds;
- the working copy of the MLX weights (published on HF, SHA matches);
- an old backup of Mac 0.6.1;
- UI test results;
- non-integrated research weights (TranslateGemma, Tower+, Hy-MT2, EuroLLM, NLLB).

Working models, OPUS direction sources, SDKs and build environments were not touched. [Manifest](maintenance/cleanup-2026-10-13.md); earlier cleanups — [12.10](maintenance/cleanup-2026-10-12.md), [deduplication](maintenance/dedup-lab-2026-10-12.md).

**iPhone signing.** According to the 13.10 check, an expired development profile caused "Kat translator is no longer available"; build 44 was rebuilt and installed over Wi-Fi via `devicectl`, data preserved. The new profile used then expires on 20.10. Check the expiry of each specific profile.
