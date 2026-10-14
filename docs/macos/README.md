# Kat translator for Mac

Mac App Store **1.0 (67)** has been archived and exported locally with updated licenses; final PKG signature, 154 binaries, sandbox/helpers and resource bundles verified. It has not been uploaded or installed. [Current package report and limits](../publication/store-license-rebuild-2026-10-14.md). Direct-release versions below are separate.

> Current: **0.6.7/build60**, macOS27+, Apple Silicon; documentation checked against source on 13 October 2026. Index 9B uses MLX+MTP2; Index 2B uses a separate llama.cpp/Metal backend. The legacy OPUS EN↔RU/UK/BE package uses a PyTorch Metal FP16 worker; catalog directions use CTranslate2 CPU INT8. Initial translation selection is Auto; saved manual choices persist. See [current state](../CURRENT_STATE.md) and [latest UI evidence](../benchmarks/ui-layout-audit-2026-10-13/README.md). Build-number sections below describe historical releases and tests.

Native SwiftUI/AppKit application for Apple Silicon. Current releases: modern macOS27+ and separate **macos15-26** download. Both use the same Index MLX+MTP2 model data; the compatibility download replaces runtime libraries, without a second model. Tested on M3 Pro/macOS27.0.1; macOS15 is a verified binary deployment floor, not a separately tested machine. [Compatibility release and evidence](../benchmarks/macos15-26-release-2026-10-12/README.md). In the modern build, translation Auto selects installed 9B then 2B on a strong device; otherwise supported OPUS then 2B and 9B. Recognition Auto is separate: classic Whisper for supported languages, Meta for additional recognition; Ultra remains optional. The retained build53 compatibility artifact predates Index 2B, catalog directions, translation Auto and the later UI changes.

Image translation uses files or clipboard, OCR and local translation, with PNG export. The right translation pane is editable: Copy and the expanded reader use the edited text, while Share and Save keep exporting the translated image independently of those edits. Above the translated text, one row of equally sized icon buttons expands the translation for reading, copies the text, shares the translated image and saves it as PNG. Share opens the native macOS sharing picker directly; Save opens the local PNG save dialog. Share prepares a private temporary PNG without asking for a save location. Saved and shared PNGs use the local date and time down to seconds as their default filename, for example `2026-10-10_17-46-23.png`. Hover hints and accessibility labels explain each action. The reader uses the entire current window; collapsing it or pressing the configured Cancel shortcut preserves the image and result. Text fields sit side by side. Native audio recording, playback, history, download integrity and RU/EN UI reuse shared code. No live camera or iOS Live Activity on Mac. Minimized/background windows keep the app running; quitting is separate.

Auto is the first row of the source-language menu in Voice, Text and Image. Choosing a language disables detection, including for global shortcuts. The separate automatic-language checkbox is removed; Speak automatically sits in the top row beside the mode tabs. iOS uses the same Auto menu entry in Voice, Text and Camera.

## Window and language picker, build31

Double-click the free title-bar area to fill the current screen while respecting the menu bar and Dock; repeat to restore the previous size and position. Voice/Text automatic-language and automatic-speech controls share one row. The language picker uses a compact560×640pt panel with full-width search,18pt names and20pt icons. Its expandable legend explains ready, downloadable, verifying and unavailable voices; the same legend is present on iPhone19. Native UI evidence and deployment details are recorded at the top of `docs/CURRENT_STATE.md`.

## Building

Prerequisites on the build Mac: Xcode, CMake, existing pinned project dependencies, Homebrew Python3.11 for packaging, prepared Wayu Python frontend and ONNX1.30.0 in `.build/wayu-env`. The **destination Mac needs none of these**.

1. `bash scripts/build-macos-runtimes.sh`
2. `python3 scripts/generate-macos-project.py`
3. `xcodebuild -project apps/macos/KatTranslatorMac.xcodeproj -scheme KatTranslatorMac -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath.build/MacDerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build`
4. `bash scripts/package-macos.sh`

Artifacts: `dist/macos/Kat-translator-<version>-build<build>-mac-arm64.dmg`, ZIP and SHA256SUMS. The build bundles/relinks non-system libraries, Python and Thai frontend. XCTest bundles and Python build configuration archives are excluded. The packaging audit rejects dependencies on absolute Homebrew/project library paths.

For the compatibility download, run `bash scripts/build-macos15-26.sh` after preparing the existing modern Index runtime. It fetches SHA-verified macOS15 MLX0.32.2 wheels and standalone Python3.11.17, builds in `.build/MacOS15DerivedData`, packages filenames with `-macos15-26`, and restores the default modern Xcode project on exit. It does not install the app or download model weights. Final bundle audit rejects any component requiring an OS newer than the declared minimum.

Current packaged builds use the existing Apple Development certificate, **not Developer ID signed or notarized**. Keeping this signing identity stable avoids ad-hoc privacy grants tied to one executable hash. Packaging selects a single available Developer ID Application identity, otherwise a single Apple Development identity; `KAT_MAC_SIGNING_IDENTITY` explicitly overrides it. Missing/ambiguous certificates fail packaging instead of silently changing identity. Explicit `KAT_MAC_SIGNING_IDENTITY=-` is reserved for disposable ad-hoc builds. Keep using the same identity for local updates. Hardened runtime remains disabled because bundled ad-hoc libraries have no Team ID. Public distribution without developer warnings still needs Developer ID signing and notarization.

When moving from an old ad-hoc build, remove Kat's old entries using minus in Accessibility and Screen Recording, then add the current `/Applications/Kat translator.app` with plus. Merely toggling the old entries may leave the old code requirement. The main window checks actual macOS permission status and removes granted-permission warnings automatically; it never treats a stale toggle as permission or requests these privileges at startup.

## Local model installation

Runtime data: `~/Library/Application Support/OfflineTranslator`, outside the replaceable.app. The Models screen supports importing existing downloaded files through the normal checksum/install pipeline.

On this Mac, Index9B, full Whisper large-v3-turbo F16, Russian Denis and English LJ Speech voices, and RU/EN OCR were installed from cached files. Whisper was copied from the connected phone. The package sources total 7,603,355,229 bytes; installed voices additionally occupy their expanded size. No model downloads were made for this transfer.

`Tools/LocalModelImport` is an explicit developer utility accepting a JSON array with `source` (file URL), `model` (ModelDescriptor) and optional `package` (ModelPackage), followed by the app-support destination. It validates using the same ModelStore/PackageStore implementation; it does not fabricate verification receipts or alter preferences. Execution evidence and exact plan: `.build/macos/local-import-plan.json` and `local-import.log`.

## Verification, 8 October

- 190 shared core tests, 2 skipped, 0 failures; 492 RU/EN catalog entries checked.
- iOS Release regression build succeeds (no phone installation). Unsigned builds require `EXPANDED_CODE_SIGN_IDENTITY_NAME='Ad Hoc'` for the existing Python packaging script.
- Mac hosted runtime tests: Index date/time translation, full Whisper on a synthetic Russian recording, English TTS PCM, embedded Thai Python tokens. Installed RU/EN setup reports ready. Latest runtime report: `.build/macos/runtime-report.json`.
- Image OCR reads synthetic `23:30` and `October 15`; invalid image data rejected.
- Native UI test opens Models/settings, types, copies and clears text; screenshot attachments in `.build/macos/ui-tests.xcresult`.
- Tests exercise generated speech samples, not a manual live microphone conversation. Microphone permission, actual speaker/headset switching and image export interaction still deserve manual device checks. Optional model families were bundled but not all were benchmarked on Mac.

Final packaging: 207 MiB installed.app, about 88 MiB DMG and 66 MiB ZIP (models stored separately). 86 bundled Mach-O files pass dependency audit, nested signatures verify, DMG checksum passes. Installed at `/Applications/Kat translator.app`; ordinary Launch Services launch remained running beyond 37 seconds with the copied model set. Evidence: `.build/macos/dependency-audit.json`, `package.log`, `dmg-verify.log`.

## Desktop layout follow-up, 8 October

Text panes now have equal content height, track window height, and scroll long output. Mac uses larger translation text (22 pt), language labels, icons, mode tabs and primary buttons. Image is inline in the main window with an explicit close button/Escape, instead of a clipped sheet. iOS uses its existing presentation and typography.

Checks: `layout-v6.xcresult` verifies equal panel geometry, mouse-resizes the actual window to 820 pt width, checks image controls remain inside the window, confirms no image sheet and returns via Close image. `testImageImportAndTranslation` in `layout-v5.xcresult` passes the complete image import/OCR/Index workflow including 23:30 and October15; that run's separate UI resize test failed because it used touch rather than mouse drag, corrected in v6. iOS regression build passed; RU/EN catalog now493 entries.

## Desktop interaction update, build 5

Empty Image opens without loading another Index context. The conversation runtime stays warm until an image actually needs translation. The original voice transcript starts expanded. The image divider works before/after import and retains minimum pane widths. Settings numeric inputs use a single label; every app-owned sheet has X/Escape, retained on nested navigation pages. Native file dialogs and system sharing popovers retain their standard Cancel/Escape behavior. Toolbar icons are larger; the Unload action uses a stable custom style.

Text, audio and translated images can be shared through macOS sharing services. Installed Telegram/WhatsApp appear when their extension or registered app handler is available. Telegram Desktop file handoff is supported; Whatsshared/apple/other Telegram file fallback copies a temporary file and prompts Cmd-V in the chosen chat. These handoffs do not select a recipient or send automatically. WhatsApp is not installed on the development Mac, so real WhatsApp delivery remains unverified. A prepared messenger draft is not a confirmed sent message.

Verified: UI close/navigation/empty divider/menu test (`polish-v3.xcresult`); three hosted tests for lazy preparation, real image translation (23:30, October 15), and special-character-safe messenger links (`polish-v2.xcresult`); iOS Release regression build; 504 RU/EN localization entries. The first UI attempt exposed local-coordinate drag under-travel; the next typing-event timeout was in XCTest, resolved in the final test by clipboard fixture input. Installed Telegram's share menu was checked without sending a message.

References for messenger integration: [Telegram deep links](https://core.telegram.org/api/links#share-links), [Telegram Desktop handler](https://github.com/telegramdesktop/tdesktop/blob/dev/Telegram/SourceFiles/core/local_url_handlers.cpp), [Apple sharing services](https://developer.apple.com/documentation/appkit/nssharingservice).

Follow-up video reproduced the old empty-Image unload. A real warm Index survives three tab cycles in `polish-warm-tabs.xcresult`. Full mode-button hit regions are explicit: nine clicks away from the label (left/right/bottom) all select the intended mode in `polish-hitareas.xcresult`.

Build 6 also leaves the Mac mode picker enabled during common model preparation, while recording/translation/model changes remain guarded. The installed `/Applications/Kat translator.app` was tested via `XCUIApplication(url:)`: explicit Prepare click, immediate navigation, completed Index preparation, then center and edge clicks through three cycles. Test passed (`polish-installed-build6.xcresult`, 29.6 seconds). Existing app replaced in place with rollback copies under `.build/macos/`; models and history were not moved or deleted. DMG/ZIP now contain build 6.


## Adaptive desktop panels, build 7

Mac-only: Settings, Models, History and nested sheets size to the presenting window (bounded width/height). Close/Escape uses a consistent native borderless X aligned to the existing navigation header; no second header/footer row. Regular and primary buttons use native bordered styles, and clearing text/Image uses the same close styling. Models headings/metadata and history text are larger. Settings retains its grouped form typography.

History previews show up to 240 Unicode characters; multiline previews collapse whitespace, and Show full text/Collapse stays above the text. This changes presentation only: stored entries and copy actions keep full original/translation text. Desktop history Share audio exclusively exports the saved translated M4A. Entries without saved audio disable that action with an explanation; no text substitution and no automatic synthesis. iPhone history presentation is unchanged.

Verification: `panels-v4.xcresult` mouse-resizes the app to 1180×900 and 820×740, checks sheet bounds and header height, opens nested model details/language setup/voices, tests X/Escape and history expansion/collapse. Three hosted checks in `panels-v2.xcresult` pass Unicode/threshold preview boundaries, panel bounds and real M4A export (including no text fallback when audio is absent). That run's UI failure caught the collapse button moving off-screen; fixed by placing it above the text. The intermediate primary-toolbar placement hid the close action on macOS; final v4 verifies the header overlay placement. iOS Release regression build and 506-entry RU/EN localization audit pass.

Style rollback snapshot: `.build/macos/panels-backup/`. Packaging audit and image verification are in `panels-package.log`, `panels-dmg-verify.log`, and `dependency-audit.json`. No model packages changed or downloaded.

Build 7 replaced `/Applications/Kat translator.app`; prior build retained in `.build/macos/previous-installed-before-build7.app`. Deep signature verification and ordinary launch (alive after 14 seconds) passed; report: `.build/macos/panels-installed-report.json`. DMG/ZIP contain the same build.

Build 8: desktop history now creates Share audio only for entries with saved audio, rather than showing a disabled button. The missing-audio explanation and delete action remain.


## Normal Quit cleanup and compact history, build 9

Removed the desktop missing-audio explanation and the empty audio row. Delete is aligned at the right of the copy actions (final placement in build 10); playback/share/divider are created only when an audio recording exists. iPhone history is unchanged.

The user's Dock Quit crashes in builds 6–8 were SIGABRT from `ggml_metal_rsets_free` during C++ static destruction: the Metal device still had live model allocations. AppKit now returns terminateLater, cancels recording/playback/inference, drains the Image and conversation backends, pauses downloads, and replies to the quit request only after unloading completes. Repeated Quit requests coalesce. A terminal AppModel state prevents pending startup/UI work from loading models again. Native libraries/assertions were not patched or bypassed.

Evidence: two hosted lifecycle tests pass (`quit-lifecycle.xcresult`); `scripts/validation/mac-quit-probe.py` launches the final packaged app as a child and sends ordinary Quit via NSRunningApplication (the Dock-style path). Cold, loaded Index, and quit-during-Index-load all exited with code 0 in 0.286/0.236/0.755 s respectively; both model scenarios record unload.complete before process exit. Metadata-only traces and child exit statuses: `.build/macos/quit-process-v1/report.json`. No force-kill is counted as a successful test. iOS Release regression build and 507-entry localization audit pass.

Build 10 follows the annotated screenshot: no lower row for entries without audio; Delete sits to the right of Copy translation / Copy original. Audio-only entries retain Delete beside Share audio. Includes the verified normal Quit fix from build 9.

Build 10 also applies KatTheme.accent to every shared desktop close/clear control and the main toolbar icons. Native button shapes and disabled states remain; iPhone controls are unchanged.

Build 10 is installed at `/Applications/Kat translator.app`; prior build saved under `.build/macos/previous-installed-before-build10.app`. Build 9 was already closed at replacement time; build 10 passed signature/dependency checks and remained alive after a fresh Launch Services launch. Evidence: `.build/macos/history-actions-installed.json`.


## In-app language and saved audio replay, build 11

Settings includes an immediately applied Russian/English/System default UI language selector on Mac and iPhone. A tap anywhere on the version/build block copies both fields and the app name; checkmark confirms it. iOS microphone mode picker is now a collapsed menu.

Shared speaker replay uses the existing complete M4A instead of synthesizing the translation again. Text, target and selected voice identity must match; missing audio or another voice falls back to synthesis. First manual translated speech is archived under its existing entry, original reading does not replace it. Copy used for playback is temporary and removed after completion/cancellation. Full details, regression results and intermediate test-harness failures: `docs/benchmarks/replay-audio-and-language/README.md`.


## Long translation context, build 18 — withdrawn

Settings now includes 2K/4K default/8K context limits and temporary document context for Index/Qwen. All models preserve paragraph structure and retry smaller pieces when generation reaches its limit. Mac18 is installed and the ad-hoc DMG/ZIP refreshed; iOS11 has the same shared behavior. Verification and known limits: [long-context report](../benchmarks/long-context/README.md).


## Context references removed, build 19 — withdrawn

The user article exposed duplication and altered meaning when injecting neighboring references. That experiment is fully removed from text/voice/recording previews; the toggle and cache are gone. Independent paragraph translation and 2K/4K/8K model windows remain. Mac19 installed and DMG/ZIP refreshed. [Comparison and removal evidence](../benchmarks/long-context/context-removal/README.md).

## Rollback to build 17 — 9 October 2026

The two sections above are historical and superseded. At the user's request, the original Mac build17 and the matching pre-experiment iPhone build10 are installed again. Sources restore whole-input translation when it fits, fixed 2048 context / 1536 input / 512 output limits, and splitting only on exceeded limits. The window-size setting and paragraph-first processor are removed. Mac18/19 DMG/ZIP/checksums and the local app copies are deleted. Existing models and history are retained. Use `dist/macos/Kat-translator-0.1.0-build17-mac-arm64.dmg` for sharing; it is the original ad-hoc distribution and was not repackaged.

## Mac21 — output budget, 9 October 2026

Mac21 succeeds Mac20's diagnostics-only result timers and is installed over the existing app. It keeps the fixed2048-token context and1536-token input limit, but allows the response to use all free context positions rather than stopping at512 tokens. Actual overflow still uses the existing split/retry path. The removed context and window-setting experiments remain removed. On the user's news article, two warm Index RU→EN runs averaged26.779s versus53.766s before; the wasted first attempt is gone. The previous Yandex article still matches original17 byte-for-byte. Three hosted tests and one native UI test pass; signature/dependency checks and DMG checksum pass. iPhone13 remains untouched. [Test evidence and limits](../benchmarks/translation-output-limit/README.md).

That build's sharing package: `dist/macos/Kat-translator-0.1.0-build21-mac-arm64.dmg` (ZIP and SHA-256 alongside it). Signing remains ad-hoc, without Developer ID/notarization. The original17 distribution is retained as rollback evidence.

## Mac22 — preflight response reservation, 9 October 2026

Before generation, count the full prompt and source separately with the selected model's tokenizer. Reserve `ceil(sourceTokens × 1.5) + 64` response positions; split using the existing sentence/word boundaries until every request fits. Progress receives the resulting part count before inference. The actual runtime limit and split/retry fallback remain for unexpectedly long responses. Fixed2048 context,1536 input cap, prompts and decoding stay unchanged. After successful Mac testing, the user authorized iPhone14 with the same policy and rebuilt runtime; its short native translation UI check passed and installation/normal launch are confirmed.

On the two user articles combined (4966 characters), Index RU→EN takes49.662s versus90.295s in Mac21, with identical final output. The discarded40.624s call is eliminated and progress starts with two parts. Both single articles stay one part and retain their prior output. Four native tests and220 core tests (2 optional voice skips) pass. [Evidence and limits](../benchmarks/translation-preflight/README.md). Mac22 DMG/ZIP is the new sharing package; signing remains ad-hoc. Previous distributions are retained.

Mac22 is installed and normally launched; installed executable/runtime match the staged package. Deep signature, dependency audit and DMG verification pass (`.build/translation-preflight/mac-installed.json`).
