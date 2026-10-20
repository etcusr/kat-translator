# iPhone in-place update and background download — 20 October 2026

## Result

Development **1.0.1 (56)** was installed over the existing **Store 1.0 (55)** on an iPhone 17 Pro running iOS 27.0.1. Both use `app.kattranslator`. Kat was not uninstalled and its data container was not cleared. This is a development-signed update over a Store installation, **not** an update delivered by the App Store. Build 56 has not been uploaded.

The previous version was identified before installation as build 55, `builtByDeveloper: false`, with its container inaccessible to development tools. A standalone UI test helper inspected that installed application without building or replacing it.

## Retained models

Before and after the update, the Models screen reported these two model IDs as downloaded and verified:

- `index-translate-9b-q4km`
- `whisper-large-v3-turbo-f16`

Immediately after installation, before launching the new application, its persistent model directory contained:

| Existing file | Bytes |
|---|---:|
| `index-translate-9b-q4km.bin` | 5,780,090,304 |
| `whisper-large-v3-turbo-f16.bin` | 1,624,555,275 |
| `vits-piper-en_US-ljspeech-high.bin` | 115,817,679 |
| `vits-piper-ru_RU-irina-medium.bin` | 67,153,308 |

These four files had identical reported metadata immediately after installation and after the separate OPUS download test. Index and Whisper were not downloaded again; the before/after UI inventories matched. No settings/history deletion or model-selection action was performed.

**Limits:** Store-container access was unavailable before the update, so no complete pre/post SHA-256 comparison or settings/history equality claim is made. The UI check establishes installed readiness, not a new translation, recognition or speech-quality benchmark. Future storage/catalog migrations still require their own acceptance.

## Background download

The OPUS Big `opus-mt-big-en-zle-int8` package was absent initially. The test started its **492.7 MB** download in Models, immediately pressed Home, and observed SpringBoard without returning to Kat until after the final background sample.

| Nominal sample after Home | Observed state |
|---|---|
| 0 seconds | Home transition; no reliable percentage |
| 15 seconds | Dynamic Island screenshot: 5% |
| 30 seconds | Dynamic Island screenshot: 28% |
| 45 seconds | Dynamic Island screenshot: 51% |
| 60 seconds | Dynamic Island screenshot: 51% |
| 75 seconds | “Model ready” notification; accessibility snapshot includes completed 100% |
| 90 seconds | Download activity no longer visible |
| Return to Kat | OPUS already marked downloaded and verified |

Sample labels are nominal: screenshot/accessibility capture adds overhead. This is not a precise transfer-throughput benchmark. The 100% value was captured in the accessibility tree; the accompanying screenshot shows the completion notification after the Island has contracted.

Completion and notification occurred **while Kat was in the background**. This proves background completion in this run and advancement beyond the reported initial stall. It does **not** prove smooth or continuously current percentages: the two 51% samples demonstrate a visible pause. The original bulk “download all recommended” path was not repeated, to avoid deleting or downloading the existing multi-gigabyte models again. Network interruption, a stale interval longer than 60 seconds, Lock Screen presentation, and prolonged suspension were not exercised.

One accessibility inconsistency was also observed: SpringBoard's parent Island label retained an older percentage while the child text and screenshot advanced. The table uses visible screenshot percentages, not that stale parent label. No VoiceOver behavior fix is claimed.

The downloaded OPUS package remains available on the phone. Its download did not explicitly change the saved model selection.

## Loading clips and partial text

- The new iPhone bundle contains no `LoadingAnimations` resources or waiting MP4/MOV clips. Their removal was implemented earlier for iOS, Mac and Android. Unrelated Python/Tk GIF resources are not translation loading clips.
- The drawn cat on the model-download progress bar is separate and remains.
- Progressive translation text is currently enabled by the Mac-only `AppModel` configuration of `showsTranslationPartials`. Its default remains false on iOS. Speech streaming and visual partial-text display are different behaviors; this task did not enable iOS partial text.

## Verification and evidence

- Signed iOS Release app/widget build: passed; both report 1.0.1 (56).
- Deep/strict signature verification with access to the system trust store: passed.
- Standalone UI inventory of Store 55: passed after opening Models via the existing downloads deep link. The first toolbar-only navigation attempt failed to open Models; it did not modify models.
- Standalone UI inventory of development 56: passed.
- Background download UI test: passed, 110.24 seconds including setup and observations.
- 12 local checks passed: Live Activity scheduler, bilingual documentation parity, build identity and release notices. The initial test command lacked the validation-module import path; the corrected invocation passed.
- Device inventory confirms installed development 1.0.1 (56); ordinary launch passed.
- Temporary UI test runner removed after testing; Kat and its data retained.

Raw device inventory, metadata, UI hierarchies, screenshots, test helper and result bundles remain private under `.build/ios-update-2026-10-20/`. They are excluded from Git because screenshots and device outputs contain personal information. Relevant bundles are `before-second.xcresult`, `after.xcresult`, and `background.xcresult`; model metadata is in `after-install-files.json` and `after-download-files.json`.

The production background publication change and filesystem regressions are described in [the preceding report](ios-download-activity-2026-10-20.md). This acceptance adds device evidence without changing that scheduling implementation.
