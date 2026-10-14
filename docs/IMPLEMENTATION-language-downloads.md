> Historical implementation report from 7 October. The dependency table, defaults and download totals below are superseded. Current setup starts with a device probe and translation Auto: Index 9B on strong devices, otherwise supported OPUS pairs and Index 2B. Apple recognition Auto uses classic Whisper/Meta; Android uses GigaAM/Parakeet for their supported languages. Ultra remains manual on Apple; WhisperKit is removed. See [current state](CURRENT_STATE.md) and the platform instructions linked there.

# Language-scoped setup, background downloads and Lock Screen progress

2026-10-07. Implementation in the working tree; device validation status below.

## Scope and dependencies

First launch: primary language on the left, target languages on the right, separate search fields. Speech recognition and spoken translations **default ON**. Reopen from Models → Set up languages and downloads. Existing users keep models and preferences; no forced onboarding or deletion.

| Function | Dependency rule |
| --- | --- |
| Translation | Index 9B when all selected languages are in its catalog; otherwise Qwen 9B with an experimental-quality notice |
| Recognition | Ultra for its supported languages; WhisperKit for other Whisper languages; Meta Omnilingual for supported remaining languages |
| Speech output | Selected voice for each selected language, deduplicating shared voice weights |
| Unavailable capabilities | Show the affected language names instead of silently promising coverage |

No small RU/EN translation model passed the project's fidelity checks. Setup therefore **does not** replace Index with a weaker small model. Previously rejected Phi and 12B are not added.

RU/EN default download sizes, decimal GB (1 GB = 1,000,000,000 bytes):

| Package | Bytes | GB |
| --- | ---: | ---: |
| Index-Translate 9B | 5,780,090,304 | 5.780 |
| Parakeet Ultra | 632,165,613 | 0.632 |
| Russian Denis | 67,190,991 | 0.067 |
| English LJ Speech | 115,817,679 | 0.116 |
| **Total** | **6,595,264,587** | **6.595 ≈ 6.60** |

WhisperKit's 1,643,077,553 bytes are no longer required for this pair. Choosing a different voice can change the total. Already installed shared files are excluded. Download size is not installed disk usage; batch preflight also reserves space for validation and unpacking.

The pipeline accepts an absent Whisper package. Ultra-only recognition, translation and playback are covered by mocks; text translation can prepare without any recognizer. Selecting a language not covered by installed recognition produces an explicit missing-model message.

## Download lifecycle

- Background URLSession per file; all selected component tasks are submitted while foregrounded, so subsequent files do not depend on a suspended app-side queue.
- Wi-Fi requests by default, with the existing explicit cellular option in Models. A resumed task retains its original request's network policy.
- Pause stores URLSession resume data. Retry uses it; when resume data is unavailable or the remote server rejects resumption, restart is explicit. This cannot guarantee every interrupted server response is resumable.
- State, task identifiers, generations and resume data survive process relaunch. System background completion waits for validation and package assembly before acknowledging delivery.
- Generation guards reject late callbacks from cancelled attempts. Queue monitors stop before pausing components to avoid an accidental immediate restart.
- Hash validation and package assembly get a finite iOS background execution allowance. If the OS suspends or terminates preparation, restoration checks staged files on next launch. Never mark a merely downloaded archive ready.
- Ordinary app switching permits background transfer. User force quit from the app switcher cancels iOS background tasks; relaunch is required. Network availability, power and OS scheduling can delay transfer.

## Notification and Live Activity

Permission for optional local notifications is requested when starting a download. Send readiness notification only after verified installation/assembly; no notification on failure, no remote push service.

`DownloadActivityExtension` uses ActivityKit/WidgetKit, with shared attributes in `apps/ios/widget/DownloadActivityAttributes.swift`. Main app declares `NSSupportsLiveActivities`. No push token, server, account or App Group is required. The extension needs its own signing profile (`app.kattranslator.downloads`; the 2026-10-14 development candidate uses a wildcard profile, explicit distribution registration is still pending).

Lock Screen and Dynamic Island show package names, received/total bytes and the same measured fraction. Tapping opens Models. Updates are throttled locally; 100% file transfer stays in verification until the package is usable. Final state remains briefly before dismissal. Pause retains measured bytes. Failure of one component does not end the activity while other transfers are running.

**Limit:** local Live Activity updates execute only when iOS runs the app. A background transfer can continue while displayed progress is stale; the activity declares a 60-second stale date and explains delayed refresh. No fake countdown or uninterrupted real-time progress guarantee. Live Activities can also be disabled by the user or ended by iOS.

## Validation

- OfflineCore: 168 tests, 2 skipped, 0 failures (`.build/language-setup-core.log`). Includes RU/EN dependency selection, mixed-language coverage, deduplicated downloads, Ultra-only full pipeline, text without ASR, pause/resume generations, aggregate completion and assembly failure.
- RU/EN localization validator passes.
- Unsigned Release build-for-testing, including widget and UI-test target: passed (`.build/language-setup-live-final.log`).
- Signed original app build (before widget target): passed (`.build/language-setup-build.log`).
- Signed widget profile created by user in Xcode. Initial installation exposed missing generated bundle version; fixed using explicit MARKETING_VERSION/CURRENT_PROJECT_VERSION on the extension.
- iPhone: `testLanguageSetupDependenciesAndSearch` passed in RU/EN, including default speech toggles, target search and adding the WhisperKit dependency for Thai. Final UI pass plus cleanup: 2 tests, 0 failures (`.build/download-cleanup-ui.xcresult`). Keyboard dismisses on selection; the total shows checking until installed files have been restored.
- Real download probe: 36,247,756 bytes across two fixture files, pause after 414,505 bytes, URLSession resume data available, received-byte display preserved, both files verified and installed while UIApplication was backgrounded. One Live Activity created; its completed Lock Screen presentation was visually checked through Notification Center (`.build/download-live-shots`). Report: `docs/benchmarks/language-downloads/download-validation.json`. Does not measure HTTP Range offset independently or prove uninterrupted progress refresh throughout suspension.
- Probe cleanup passed; only fixture files removed, user model files preserved. Normal project generation excludes the DOWNLOAD_VALIDATION code. Opt-in build uses OT_DOWNLOAD_VALIDATION_BUILD=1; XCTest runner needs TEST_RUNNER_OT_DOWNLOAD_VALIDATION_BUILD=1. No forced-quit, reboot, multi-hour suspension or actual network-loss test; resume test used explicit pause.
- Local readiness notifications implemented; permission prompt and delivered notification were not exercised in the bounded download fixture. Do not claim notification delivery tested.

Final normal build: signed and installed on iPhone, `testLanguageSetupDependenciesAndSearch` passed again after grouping voice components and fixing disabled-button contrast (`.build/language-setup-production.xcresult`). The app was relaunched without test arguments. Widget version metadata 0.1.0 (3) verified; diagnostic download fixture excluded from final app binary.
