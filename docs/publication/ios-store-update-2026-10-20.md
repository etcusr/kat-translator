# iOS 1.0.1 (57) — App Store update, 20 October 2026

## Package and upload

The iOS-only Release archive was exported, verified and uploaded. Xcode reported `Upload succeeded` and `EXPORT SUCCEEDED` at 20:11 Moscow time. No macOS archive, Store build or review submission was changed.

- Marketing version **1.0.1**, build **57**, matching app and Live Activity extension.
- Source: `b6e19a9` iOS implementation; source identity **ios-a91925f4606a1672**.
- IPA: `dist/ios/store/Kat-translator-1.0.1-build57.ipa`, **66,865,402 bytes**, SHA-256 `e8ee4b3c9317e1def02cb0e8d0d057edfc18f563e98edfdff17a65d4f02caa98`.
- 144 repository checks passed. The source-membership fixture was refreshed only to remove the intentionally deleted loading-video players/resources; no application source changed for this release task.
- Deep/strict signatures, all 72 Mach-O binaries/signers, 70 framework deployment ranges, two distribution profiles, app/widget version parity, nine privacy manifests and 46 license notices passed. No loading-video resources, test bundles or private audio probes are present.
- The archive and previously device-tested development 57 each reproduce their embedded source fingerprint from the same current source files and recorded build settings. Their IDs differ because compiler module-map paths differ between archive and development builds.
- Apple reported 70 missing-dSYM warnings for prebuilt third-party frameworks. These did not block upload; crash symbolication inside those frameworks is limited.

## Included changes and limits

Index 9B partial translation text is visible in Text and Voice, without a blocking loading video. Background download Live Activities flush queued completion updates and indicate stale progress; iOS suspension still prevents a guarantee of continuous percentage updates. Model storage, IDs and weights are unchanged.

[Development build 57 acceptance](ios-partial-text-2026-10-20.md) covers real-device Text partial/cancel/final behavior and 102 focused core tests. [Earlier in-place Store 55 → development 56 acceptance](ios-update-acceptance-2026-10-20.md) covers retained model readiness and a completed background OPUS download. These are prior device results, not a fresh TestFlight installation of the Store archive; no new live-microphone test is claimed.

## Store metadata

Created iOS version **1.0.1** in App Store Connect. EN/RU/ES/TR descriptions, promotional copy, keywords and release notes are prepared in `2026-10-14/ios/`. AI wording describes local on-device models, not guaranteed translation quality. README, project descriptions and the public site use the same positioning. The 72 prepared fields across eight platform/locales satisfy length/language checks.

Mac AI copy is prepared locally in `2026-10-14/macos/`; applying it after the current review/publication is an explicit bilingual BACKLOG item. The current Mac Store submission was left untouched.

Apple processing completed: TestFlight shows **1.0.1 (57), Ready to Submit**. Build **57** is selected and saved for iOS **1.0.1**; selection was verified after reloading the page. The version remains **Prepare for Submission**, with **Add for Review** available. All four iOS localizations were reopened and their four text fields exactly matched the prepared files. Manual release remains selected; no App Review submission or automatic release has been requested by this release task.

Detailed package hashes/checks: [JSON](ios-store-update-2026-10-20.json). Signing/upload logs, full browser snapshots and device identifiers remain private under `.build/ios-store-2026-10-20/`.

## Source publication

Release commit `2795c25` was pushed to `origin/main`; the remote SHA was verified. GitHub Pages [deployment](https://github.com/etcusr/kat-translator/actions/runs/39464925943) succeeded. The public page at https://etcusr.github.io/kat-translator/ matches committed `site/index.html` byte for byte (SHA-256 `f8ee23b8c2398f06b96a1cc2b4cce13f481067dd2f15917858b11a9e44016f4c`). Unfinished files from other experiments were not staged.
