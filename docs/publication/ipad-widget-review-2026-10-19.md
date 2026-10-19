# Widget Gallery review investigation — 19 October 2026

## Finding

Kat has no gallery widget. `DownloadActivityBundle` registers exactly one configuration: `ModelDownloadActivity`, which uses ActivityKit `ActivityConfiguration`. It does not register a Home Screen/Lock Screen widget with a timeline provider. Consequently there is no ordinary widget to add from the Widget Gallery, on iPhone or iPad. This explains the reported gallery absence without establishing any separate runtime failure of Live Activities on iPad.

The included extension is used exclusively to display model-download Live Activities. Apple describes Live Activities as distinct from widgets despite their use of WidgetKit. They appear for an active task rather than being added through the widget picker. [Apple Live Activity documentation](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) · [ActivityConfiguration](https://developer.apple.com/documentation/widgetkit/activityconfiguration).

## Checks performed

- Reviewed the current complete extension and confirmed that `DownloadActivityWidget.swift` is unchanged since the initial public source import, predating builds 52 and 55.
- Inspected both retained archives: `DownloadActivityExtension.appex` is embedded, uses the WidgetKit extension point, matches build 52/55 respectively and declares family `[1]`. Both containing apps enable `NSSupportsLiveActivities`.
- Both extension signatures passed `codesign --verify --strict` with access to the system trust store. Initial sandbox-only checks returned `CSSMERR_TP_NOT_TRUSTED`; that result was not treated as an artifact defect.
- Inspected the actual download trigger: `ModelDownloader.start` calls `DownloadLiveActivity.started`; that implementation requests an Activity only while the app is active and Live Activities are enabled. It updates measured progress locally, declares stale content and ends the activity after completion. No activity is expected simply from installing or opening the app without a download.
- Checked prepared iOS descriptions/promotional/reviewer text for RU/EN/ES/TR; they did not advertise a gallery widget. The remotely edited App Store Connect text was not accessed, so it may differ.
- The available device inventory contains an iPhone, no iPad. CoreSimulator reports no installed runtimes or available simulators. **No fresh iPad or iPhone runtime test was performed.** This is source/package diagnosis, not device acceptance.

## Correction and next action

Added explicit Live Activity vs. Widget Gallery clarification and download-based verification steps to the prepared iOS reviewer notes, including their existing English mirror. Runtime code and supported device families are unchanged: adding a gallery widget would be a new product feature, not repairing an existing implementation.

The recommended next action is to send Apple the clarification and ask them to reassess the gallery expectation. If they instead observed a Live Activity failing during an actual download, obtain those steps and investigate that runtime issue on an iPad. Approval remains open. No reply was sent, no App Store metadata was changed and no new binary was built or uploaded.

The release queue now distinguishes diagnosed gallery absence from unverified iPad Live Activity behavior. The owner clarified that no gallery widget was expected and asked where the review expectation came from. The review message does not establish that source; mistaking the WidgetKit extension for a gallery widget is only a hypothesis. No new widget feature was implemented.

## Validation

Prepared metadata validator (8 localizations, 72 fields, 2 reviewer-note copies), bilingual documentation parity and local-link/whitespace checks were run for the documentation change. No production behavior changed; no full application build or device acceptance is claimed.
