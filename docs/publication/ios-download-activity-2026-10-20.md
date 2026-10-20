# iOS download Live Activity and update retention — 20 October 2026

## Evidence and scope

The owner reported that Store iOS 1.0 (55) stopped advancing in Dynamic Island near 10–11% increments after backgrounding, while returning to Kat showed higher progress. No device trace was collected; the precise percentage pattern is not reproduced or hard-coded in the app.

The code uses background URLSession transfers and local ActivityKit publications only. iOS can continue the transfer while the application is suspended. The existing two-second publication throttle cannot run while suspended. Apple documents these boundaries in [background downloads](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background) and [Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities). This is a supported explanation for the background-only observation, not proof of a particular suspension timestamp.

A separate ordering defect was verified in source: `urlSessionDidFinishEvents` persisted state (scheduling a deferred publication) and immediately called the system completion handler. Publication was not awaited before relinquishing background execution. Stale information was explained on the Lock Screen but not in Dynamic Island.

## Source changes

- Await `DownloadLiveActivity.flush()` before the background URLSession completion handler. It drains through the caller's revision, including a snapshot queued during an in-flight ActivityKit update.
- Refresh the snapshot on application activation/backgrounding with a short, expiring UIKit background allowance. This allowance only covers publication, not the entire transfer.
- Retain the existing 60-second stale deadline. The compact Island replaces a stale percentage with a clock; the expanded Island explains that progress awaits new system data. The bar is never extrapolated from time.
- Add a no-op flush on macOS to preserve the shared downloader contract.

These changes do **not** guarantee continuously updating percentages during suspension. No notification server, frequent-push entitlement or artificial keep-alive was added. A real phone background download remains an acceptance check; this report does not claim the original symptom has disappeared on-device.

## Model retention

Application updates must retain downloaded models, receipts, settings and history. Current Apple model storage is persistent Application Support/OfflineTranslator, separate from the application bundle. The loader recognizes unchanged assets by ID, byte count and checksum; display titles and mirror URLs are not weight identity. These paths, IDs, weights and migration code were not changed.

New tests move a populated model/package container, reopen its stores and verify exact file bytes and readiness without downloading. Single-file testing also changes title and URL. Existing retirement tests verify scoped historic removals preserve current models/voices/recognition/history. This is a local filesystem simulation, not an actual App Store upgrade. The release rule in GIT_WORKFLOW requires in-place device upgrade acceptance whenever storage/catalog/migration behavior changes; do not uninstall or wipe data as an update step.

## Verification

- Production Live Activity scheduler compiled on macOS against controlled ActivityKit/UIKit doubles: absent activity, queued progress, blocked in-flight publication with a newer snapshot, and final completion pass. The pre-change implementation has no awaited flush API and fails the regression compile. The doubles verify async ordering, not OS rendering, suspension or scheduling.
- 28 focused OfflineCore tests pass: ModelStore, PackageStore, DownloadProgress and RetiredTranslationModels; includes the two new relocation cases.
- Unsigned iOS Debug application and widget build succeeds with Xcode 27.1. No version change, installation, Store upload or push.
- Documentation parity and staged diff checks are recorded at task completion.

Installed Store data was not accessed, removed or rewritten. Required next acceptance: normal signed update over an existing install, existing models reused without downloading; a controlled real-device download followed by backgrounding, stale state and eventual completion. Continuous progress during suspension remains an OS/runtime limitation.
