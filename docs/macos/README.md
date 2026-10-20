# Kat translator for Mac

**English** | [Русский](README.ru.md)

**Local source update, 20 October:** Settings → Memory now includes a translation idle-unload timer (default 5 minutes, 1–60 minutes). Weights are reused while resident and reload automatically after expiry. Settings → Experimental has an off-by-default Index 9B chunk option: earlier partial text, with possible context errors and longer total time. Manual unload and memory-saving behavior remain. Release test-build and real MLX checks passed; no new Store/direct package or Applications installation. [Results and limits](../benchmarks/mac-production-residency-2026-10-20/README.md).

Local DMG/ZIP packages are updated to **0.6.8 (61)** for macOS 27+ and separately macOS 15–26. Both include the current recognition/speech and Image fixes, including paragraphs and diagnostic timings. Extracted contents, signatures, checksums and library deployment limits passed verification. Keep at most three releases per line: modern 59/60/61, compatible 53/61 (only two exist). The corrected installed copy remains 0.6.7 (60). [Package checks](../publication/mac-direct-2026-10-18.md).

**iOS 1.0 (54) and Mac App Store 1.0 (76)** were verified and uploaded to App Store Connect. They include recognition preparation before the microphone, recognition release on Text/Camera, and the off-by-default date/time correction setting. iPhone AudioQueue capture reduces first-buffer latency from about 1.40 to 0.28 seconds in development-device measurements. During-recording processing and prior streamed-speech fixes are preserved. Mac also reconstructs OCR paragraphs and shows recognition/translation timings when diagnostics is enabled. Signatures, entitlements, resources and all 143 project checks passed. Apple processing and TestFlight installation are not yet confirmed; the owner selects builds for App Review. [Verification and upload](../publication/apple-capture-store-2026-10-18.md).

The installed `/Applications/Kat translator.app` was refreshed with the Image fixes: version remains **0.6.7 (60)**, new source identity **mac-8378c215e7c13deb**. Signature verification, matching 25,206 file/link entries and normal launch passed; preferences were preserved. Direct DMG/ZIP were subsequently refreshed to 61 as described above. [Installation checks](../benchmarks/mac-image-paragraphs-2026-10-18/installed.md).

**Previous upload, 17 October:** **iOS 1.0 (53) and Mac App Store 1.0 (71)** were built from the corrected sources, verified and uploaded to App Store Connect. They include complete streamed speech, exact whitespace handling to avoid replay, contextual Russian ordinals and Mac MLX partial output. Both packages contain the current 13 loading clips. Project validation: 143 PASS. Apple processing, TestFlight installation and build selection for review are not yet confirmed. [Checks and upload result](../publication/apple-speech-store-2026-10-17.md).

The 17 October development build was installed at `/Applications/Kat translator.app` as **0.6.7 (60)**, source fingerprint `mac-c075be03543c17ac`. Complete streamed sentences, whitespace handling, contextual Russian ordinals and default MLX partial output are included. Four fresh runtime checks and signature/dependency/normal-launch checks passed. Modern DMG/ZIP now contain the corrected app: [verified packages and hashes](../benchmarks/mac-speech-install-2026-10-17/packages.md). App Store 76 now contains these fixes; the separate macOS 15–26 packages remain unchanged. [Installation and verification](../benchmarks/mac-speech-install-2026-10-17/README.md).

Native SwiftUI/AppKit application for Apple Silicon. There are two distribution channels built from the same sources:

| Channel | Version | Bundle ID | Signing | Status |
|---|---|---|---|---|
| **Mac App Store** | **1.0 / build76** (uploaded; processing result pending) | `app.kattranslator` (shared with iOS) | Apple Distribution, App Sandbox | Build76 uploaded; owner will select the build and submit for review |
| Direct download (DMG/ZIP) | **0.6.8 / build61**, modern and separate **macos15-26** variants | `org.openoffline.translator.mac` | Apple Development, no sandbox | Not Developer ID signed or notarized |

The direct build requires macOS 27+ (the compatibility download declares macOS 15). Index 9B uses MLX + MTP2; Index 2B uses a separate llama.cpp/Metal backend. The legacy OPUS EN↔RU/UK/BE package uses a PyTorch Metal FP16 worker; catalog directions use CTranslate2 CPU INT8. The initial translation selection is Auto: installed 9B, then 2B on a strong device; otherwise a supported OPUS direction, then 2B and 9B. Saved manual choices persist. Recognition Auto is separate: Parakeet (Core ML) or classic Whisper for supported languages, Meta Omnilingual for additional recognition. See [current state](../CURRENT_STATE.md), [store build report](../publication/macos-appstore-build-2026-10-14.md) and [latest runtime acceptance](../publication/runtime-acceptance-2026-10-14.md).

Image translation uses files or the clipboard, OCR and local translation, with PNG export. The right translation pane is editable: Copy and the expanded reader use the edited text, while Share and Save keep exporting the translated image independently of those edits. Share opens the native macOS sharing picker; Save opens the PNG save dialog; default file names use the local date and time to the second, for example `2026-10-10_17-46-23.png`. Native audio recording, playback, history, download integrity and the RU/EN/ES/TR interface reuse shared code. There is no live camera or iOS Live Activity on Mac. Minimized/background windows keep the app running; quitting is separate.

Auto is the first row of the source-language menu in Voice, Text and Image. Choosing a language disables detection, including for global shortcuts. "Speak automatically" sits in the top row beside the mode tabs.

## Mac App Store build

The store variant is produced by `scripts/archive-macos-appstore.sh` (`KAT_MAC_STORE_BUILD=<n> scripts/archive-macos-appstore.sh export|upload`). It generates a separate, ignored Xcode project in `.build/macos-store-project/` in which only the app target gets the store bundle ID, the store `Info.plist` (version 1.0, `ITSAppUsesNonExemptEncryption = NO`), `apps/macos/KatMacStore.entitlements` (App Sandbox, microphone, user-selected files, outgoing network) and automatic signing. SwiftPM resource bundles keep their own identifiers. The regular project and the direct build are unchanged.

Store-only packaging rules (in `scripts/bundle-macos-runtimes.py`, active when `ENABLE_APP_SANDBOX=YES`):

- the OPUS GPU helper `Contents/MacOS/OpusPython` and `torch/bin/torch_shm_manager` are signed with sandbox + inherit; `protoc` is omitted;
- no TLS/crypto implementation is shipped: Python `_ssl`/`_hashlib`, `libssl`/`libcrypto` and `hf_xet` (rustls) are omitted; `index_mlx.py` installs an inert `ssl` module so that `mlx_lm` can be imported offline;
- codeless SwiftPM resource bundles lose their separate development signature; the app signature seals them.

The script stops if the archive contains XCTest bundles, unsandboxed executables, development-signed resource bundles, a resource bundle reusing the app ID or OpenSSL/rustls/BoringSSL markers. Details, test results inside the sandbox and the history of builds 61–66: [store build report](../publication/macos-appstore-build-2026-10-14.md).

## Building the direct release

Prerequisites on the build Mac: Xcode, CMake, the pinned project dependencies, Homebrew Python 3.11 for packaging, the prepared Wayu Python frontend and ONNX Runtime 1.30.0 in `.build/wayu-env`. The **destination Mac needs none of these**.

1. `bash scripts/build-macos-runtimes.sh`
2. `python3 scripts/generate-macos-project.py`
3. `xcodebuild -project apps/macos/KatTranslatorMac.xcodeproj -scheme KatTranslatorMac -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/MacDerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build`
4. `bash scripts/package-macos.sh`

Artifacts: `dist/macos/Kat-translator-<version>-build<build>-mac-arm64.dmg`, ZIP and SHA256SUMS. The build bundles and relinks non-system libraries, Python and the Thai frontend. XCTest bundles and Python build configuration archives are excluded. The packaging audit rejects dependencies on absolute Homebrew/project library paths.

For the compatibility download, run `bash scripts/build-macos15-26.sh` after preparing the modern Index runtime. It fetches SHA-verified macOS 15 MLX 0.32.2 wheels and standalone Python 3.11.17, builds in `.build/MacOS15DerivedData`, packages file names with `-macos15-26` and restores the default modern Xcode project on exit. It does not install the app or download model weights. The final bundle audit rejects any component requiring an OS newer than the declared minimum.

Direct builds use the existing Apple Development certificate, **not Developer ID signed or notarized**. Keeping this signing identity stable avoids ad-hoc privacy grants tied to one executable hash. Packaging selects a single available Developer ID Application identity, otherwise a single Apple Development identity; `KAT_MAC_SIGNING_IDENTITY` explicitly overrides it. Missing or ambiguous certificates fail packaging instead of silently changing the identity. `KAT_MAC_SIGNING_IDENTITY=-` is reserved for disposable ad-hoc builds. Hardened runtime remains disabled for the direct build. Public distribution outside the App Store without warnings still needs Developer ID signing and notarization.

When moving from an old ad-hoc build, remove Kat's old entries with minus in Accessibility and Screen Recording, then add the current `/Applications/Kat translator.app` with plus. Merely toggling the old entries may keep the old code requirement. The main window checks the actual macOS permission status and removes warnings for granted permissions automatically; it never treats a stale toggle as permission or requests these privileges at startup.

## Testing notes

UI tests drive the app through XCTest and need the owner to approve UI automation once per session (or a pre-authorized automation mode). Run test builds from a DerivedData directory outside `~/Downloads`: otherwise macOS asks for access to the Downloads folder at launch and the test runner reports "hung before establishing connection". Sandboxed store-configuration tests use separate test entitlements with a read-only exception for already downloaded models; opt-in helpers `testSandboxSeedModels` and `testSandboxResetContainerData` prepare and clean the sandbox container.

## Local model installation (direct build)

Runtime data of the direct build: `~/Library/Application Support/OfflineTranslator`; the sandboxed store build keeps its data inside its own container, outside the replaceable .app. The Models screen supports importing existing downloaded files through the normal checksum/install pipeline.

On this Mac, Index9B, full Whisper large-v3-turbo F16, Russian Denis and English LJ Speech voices, and RU/EN OCR were installed from cached files. Whisper was copied from the connected phone. The package sources total 7,603,355,229 bytes; installed voices additionally occupy their expanded size. No model downloads were made for this transfer.

`Tools/LocalModelImport` is an explicit developer utility accepting a JSON array with `source` (file URL), `model` (ModelDescriptor) and optional `package` (ModelPackage), followed by the app-support destination. It validates using the same ModelStore/PackageStore implementation; it does not fabricate verification receipts or alter preferences. Execution evidence and exact plan: `.build/macos/local-import-plan.json` and `local-import.log`.


## Historical build notes

The sections below describe historical builds and tests in chronological order. They are kept as evidence and are not the current specification.

### Window and language picker, build 31

Double-click the free title-bar area to fill the current screen while respecting the menu bar and Dock; repeat to restore the previous size and position. Voice/Text automatic-language and automatic-speech controls share one row. The language picker uses a compact560×640pt panel with full-width search,18pt names and20pt icons. Its expandable legend explains ready, downloadable, verifying and unavailable voices; the same legend is present on iPhone19. Native UI evidence and deployment details are recorded at the top of `docs/CURRENT_STATE.md`.

### Verification, 8 October

- 190 shared core tests, 2 skipped, 0 failures; 492 RU/EN catalog entries checked.
- iOS Release regression build succeeds (no phone installation). Unsigned builds require `EXPANDED_CODE_SIGN_IDENTITY_NAME='Ad Hoc'` for the existing Python packaging script.
- Mac hosted runtime tests: Index date/time translation, full Whisper on a synthetic Russian recording, English TTS PCM, embedded Thai Python tokens. Installed RU/EN setup reports ready. Latest runtime report: `.build/macos/runtime-report.json`.
- Image OCR reads synthetic `23:30` and `October 15`; invalid image data rejected.
- Native UI test opens Models/settings, types, copies and clears text; screenshot attachments in `.build/macos/ui-tests.xcresult`.
- Tests exercise generated speech samples, not a manual live microphone conversation. Microphone permission, actual speaker/headset switching and image export interaction still deserve manual device checks. Optional model families were bundled but not all were benchmarked on Mac.

Final packaging: 207 MiB installed.app, about 88 MiB DMG and 66 MiB ZIP (models stored separately). 86 bundled Mach-O files pass dependency audit, nested signatures verify, DMG checksum passes. Installed at `/Applications/Kat translator.app`; ordinary Launch Services launch remained running beyond 37 seconds with the copied model set. Evidence: `.build/macos/dependency-audit.json`, `package.log`, `dmg-verify.log`.

### Desktop layout follow-up, 8 October

Text panes now have equal content height, track window height, and scroll long output. Mac uses larger translation text (22 pt), language labels, icons, mode tabs and primary buttons. Image is inline in the main window with an explicit close button/Escape, instead of a clipped sheet. iOS uses its existing presentation and typography.

Checks: `layout-v6.xcresult` verifies equal panel geometry, mouse-resizes the actual window to 820 pt width, checks image controls remain inside the window, confirms no image sheet and returns via Close image. `testImageImportAndTranslation` in `layout-v5.xcresult` passes the complete image import/OCR/Index workflow including 23:30 and October15; that run's separate UI resize test failed because it used touch rather than mouse drag, corrected in v6. iOS regression build passed; RU/EN catalog now493 entries.

### Desktop interaction update, build 5

Empty Image opens without loading another Index context. The conversation runtime stays warm until an image actually needs translation. The original voice transcript starts expanded. The image divider works before/after import and retains minimum pane widths. Settings numeric inputs use a single label; every app-owned sheet has X/Escape, retained on nested navigation pages. Native file dialogs and system sharing popovers retain their standard Cancel/Escape behavior. Toolbar icons are larger; the Unload action uses a stable custom style.

Text, audio and translated images can be shared through macOS sharing services. Installed Telegram/WhatsApp appear when their extension or registered app handler is available. Telegram Desktop file handoff is supported; Whatsshared/apple/other Telegram file fallback copies a temporary file and prompts Cmd-V in the chosen chat. These handoffs do not select a recipient or send automatically. WhatsApp is not installed on the development Mac, so real WhatsApp delivery remains unverified. A prepared messenger draft is not a confirmed sent message.

Verified: UI close/navigation/empty divider/menu test (`polish-v3.xcresult`); three hosted tests for lazy preparation, real image translation (23:30, October 15), and special-character-safe messenger links (`polish-v2.xcresult`); iOS Release regression build; 504 RU/EN localization entries. The first UI attempt exposed local-coordinate drag under-travel; the next typing-event timeout was in XCTest, resolved in the final test by clipboard fixture input. Installed Telegram's share menu was checked without sending a message.

References for messenger integration: [Telegram deep links](https://core.telegram.org/api/links#share-links), [Telegram Desktop handler](https://github.com/telegramdesktop/tdesktop/blob/dev/Telegram/SourceFiles/core/local_url_handlers.cpp), [Apple sharing services](https://developer.apple.com/documentation/appkit/nssharingservice).

Follow-up video reproduced the old empty-Image unload. A real warm Index survives three tab cycles in `polish-warm-tabs.xcresult`. Full mode-button hit regions are explicit: nine clicks away from the label (left/right/bottom) all select the intended mode in `polish-hitareas.xcresult`.

Build 6 also leaves the Mac mode picker enabled during common model preparation, while recording/translation/model changes remain guarded. The installed `/Applications/Kat translator.app` was tested via `XCUIApplication(url:)`: explicit Prepare click, immediate navigation, completed Index preparation, then center and edge clicks through three cycles. Test passed (`polish-installed-build6.xcresult`, 29.6 seconds). Existing app replaced in place with rollback copies under `.build/macos/`; models and history were not moved or deleted. DMG/ZIP now contain build 6.


### Adaptive desktop panels, build 7

Mac-only: Settings, Models, History and nested sheets size to the presenting window (bounded width/height). Close/Escape uses a consistent native borderless X aligned to the existing navigation header; no second header/footer row. Regular and primary buttons use native bordered styles, and clearing text/Image uses the same close styling. Models headings/metadata and history text are larger. Settings retains its grouped form typography.

History previews show up to 240 Unicode characters; multiline previews collapse whitespace, and Show full text/Collapse stays above the text. This changes presentation only: stored entries and copy actions keep full original/translation text. Desktop history Share audio exclusively exports the saved translated M4A. Entries without saved audio disable that action with an explanation; no text substitution and no automatic synthesis. iPhone history presentation is unchanged.

Verification: `panels-v4.xcresult` mouse-resizes the app to 1180×900 and 820×740, checks sheet bounds and header height, opens nested model details/language setup/voices, tests X/Escape and history expansion/collapse. Three hosted checks in `panels-v2.xcresult` pass Unicode/threshold preview boundaries, panel bounds and real M4A export (including no text fallback when audio is absent). That run's UI failure caught the collapse button moving off-screen; fixed by placing it above the text. The intermediate primary-toolbar placement hid the close action on macOS; final v4 verifies the header overlay placement. iOS Release regression build and 506-entry RU/EN localization audit pass.

Style rollback snapshot: `.build/macos/panels-backup/`. Packaging audit and image verification are in `panels-package.log`, `panels-dmg-verify.log`, and `dependency-audit.json`. No model packages changed or downloaded.

Build 7 replaced `/Applications/Kat translator.app`; prior build retained in `.build/macos/previous-installed-before-build7.app`. Deep signature verification and ordinary launch (alive after 14 seconds) passed; report: `.build/macos/panels-installed-report.json`. DMG/ZIP contain the same build.

Build 8: desktop history now creates Share audio only for entries with saved audio, rather than showing a disabled button. The missing-audio explanation and delete action remain.


### Normal Quit cleanup and compact history, build 9

Removed the desktop missing-audio explanation and the empty audio row. Delete is aligned at the right of the copy actions (final placement in build 10); playback/share/divider are created only when an audio recording exists. iPhone history is unchanged.

The user's Dock Quit crashes in builds 6–8 were SIGABRT from `ggml_metal_rsets_free` during C++ static destruction: the Metal device still had live model allocations. AppKit now returns terminateLater, cancels recording/playback/inference, drains the Image and conversation backends, pauses downloads, and replies to the quit request only after unloading completes. Repeated Quit requests coalesce. A terminal AppModel state prevents pending startup/UI work from loading models again. Native libraries/assertions were not patched or bypassed.

Evidence: two hosted lifecycle tests pass (`quit-lifecycle.xcresult`); `scripts/validation/mac-quit-probe.py` launches the final packaged app as a child and sends ordinary Quit via NSRunningApplication (the Dock-style path). Cold, loaded Index, and quit-during-Index-load all exited with code 0 in 0.286/0.236/0.755 s respectively; both model scenarios record unload.complete before process exit. Metadata-only traces and child exit statuses: `.build/macos/quit-process-v1/report.json`. No force-kill is counted as a successful test. iOS Release regression build and 507-entry localization audit pass.

Build 10 follows the annotated screenshot: no lower row for entries without audio; Delete sits to the right of Copy translation / Copy original. Audio-only entries retain Delete beside Share audio. Includes the verified normal Quit fix from build 9.

Build 10 also applies KatTheme.accent to every shared desktop close/clear control and the main toolbar icons. Native button shapes and disabled states remain; iPhone controls are unchanged.

Build 10 is installed at `/Applications/Kat translator.app`; prior build saved under `.build/macos/previous-installed-before-build10.app`. Build 9 was already closed at replacement time; build 10 passed signature/dependency checks and remained alive after a fresh Launch Services launch. Evidence: `.build/macos/history-actions-installed.json`.


### In-app language and saved audio replay, build 11

Settings includes an immediately applied Russian/English/System default UI language selector on Mac and iPhone. A tap anywhere on the version/build block copies both fields and the app name; checkmark confirms it. iOS microphone mode picker is now a collapsed menu.

Shared speaker replay uses the existing complete M4A instead of synthesizing the translation again. Text, target and selected voice identity must match; missing audio or another voice falls back to synthesis. First manual translated speech is archived under its existing entry, original reading does not replace it. Copy used for playback is temporary and removed after completion/cancellation. Full details, regression results and intermediate test-harness failures: `docs/benchmarks/replay-audio-and-language/README.md`.


### Long translation context, build 18 — withdrawn

Settings now includes 2K/4K default/8K context limits and temporary document context for Index/Qwen. All models preserve paragraph structure and retry smaller pieces when generation reaches its limit. Mac18 is installed and the ad-hoc DMG/ZIP refreshed; iOS11 has the same shared behavior. Verification and known limits: [long-context report](../benchmarks/long-context/README.md).


### Context references removed, build 19 — withdrawn

The user article exposed duplication and altered meaning when injecting neighboring references. That experiment is fully removed from text/voice/recording previews; the toggle and cache are gone. Independent paragraph translation and 2K/4K/8K model windows remain. Mac19 installed and DMG/ZIP refreshed. [Comparison and removal evidence](../benchmarks/long-context/context-removal/README.md).

### Rollback to build 17 — 9 October 2026

The two sections above are historical and superseded. At the user's request, the original Mac build17 and the matching pre-experiment iPhone build10 are installed again. Sources restore whole-input translation when it fits, fixed 2048 context / 1536 input / 512 output limits, and splitting only on exceeded limits. The window-size setting and paragraph-first processor are removed. Mac18/19 DMG/ZIP/checksums and the local app copies are deleted. Existing models and history are retained. Use `dist/macos/Kat-translator-0.1.0-build17-mac-arm64.dmg` for sharing; it is the original ad-hoc distribution and was not repackaged.

### Mac21 — output budget, 9 October 2026

Mac21 succeeds Mac20's diagnostics-only result timers and is installed over the existing app. It keeps the fixed2048-token context and1536-token input limit, but allows the response to use all free context positions rather than stopping at512 tokens. Actual overflow still uses the existing split/retry path. The removed context and window-setting experiments remain removed. On the user's news article, two warm Index RU→EN runs averaged26.779s versus53.766s before; the wasted first attempt is gone. The previous Yandex article still matches original17 byte-for-byte. Three hosted tests and one native UI test pass; signature/dependency checks and DMG checksum pass. iPhone13 remains untouched. [Test evidence and limits](../benchmarks/translation-output-limit/README.md).

That build's sharing package: `dist/macos/Kat-translator-0.1.0-build21-mac-arm64.dmg` (ZIP and SHA-256 alongside it). Signing remains ad-hoc, without Developer ID/notarization. The original17 distribution is retained as rollback evidence.

### Mac22 — preflight response reservation, 9 October 2026

Before generation, count the full prompt and source separately with the selected model's tokenizer. Reserve `ceil(sourceTokens × 1.5) + 64` response positions; split using the existing sentence/word boundaries until every request fits. Progress receives the resulting part count before inference. The actual runtime limit and split/retry fallback remain for unexpectedly long responses. Fixed2048 context,1536 input cap, prompts and decoding stay unchanged. After successful Mac testing, the user authorized iPhone14 with the same policy and rebuilt runtime; its short native translation UI check passed and installation/normal launch are confirmed.

On the two user articles combined (4966 characters), Index RU→EN takes49.662s versus90.295s in Mac21, with identical final output. The discarded40.624s call is eliminated and progress starts with two parts. Both single articles stay one part and retain their prior output. Four native tests and220 core tests (2 optional voice skips) pass. [Evidence and limits](../benchmarks/translation-preflight/README.md). Mac22 DMG/ZIP is the new sharing package; signing remains ad-hoc. Previous distributions are retained.

Mac22 is installed and normally launched; installed executable/runtime match the staged package. Deep signature, dependency audit and DMG verification pass (`.build/translation-preflight/mac-installed.json`).


[Release51/70 package checks and upload evidence](../publication/signed-sdks-release-2026-10-14.md).
