# Android packages and shared catalogs

**English** | [Русский](PACKAGE-STORAGE.ru.md)

> Technical reference written during the 0.3.x stage. Since 0.4.x the initial translation choice is "Auto" (see [current state](../CURRENT_STATE.md)); statements below that call OPUS Big the Android default are historical.

`PackageRepository` is owned once per process by `PackageDownloads`, shared by the
Android ViewModel and foreground service. Its `catalog` comes
directly from the same `assets/catalogs` JSON files used by Apple. No model weights
are included in the APK or copied into an Android source folder.

`scripts/android/generate-package-capabilities.py --check` verifies generated
language mappings against the shared Swift definitions. The generated metadata
contains exact Whisper, Omnilingual and Supertonic language codes and pinned Wayu
descriptors. `android-ocr.json` describes the additional PP-OCR detector needed on
Android, where Apple Vision is unavailable. Its pinned revision, size and SHA-256
come from the upstream Hugging Face LFS tree.

## Runtime API

The repository exposes `catalog`, `states: StateFlow<Map<String, PackageStatus>>`,
`start`, `pause`, `cancel`, `remove`, `importFile`, `installedPath`, and `file`.
`restored` becomes true after startup verification. User download/import actions
must use `PackageDownloads` so Android receives a foreground service request.
`OfflinePackage.backend`, `languages`, `runtimeLanguage` and `unavailableReason`
describe usable engines and exact language constraints. Runtime holders should
keep an `acquire(id)` lease while native code reads or maps a package; removal is
rejected while the lease is active.

`installedPath` returns a weight file for Index, Whisper and OCR; it returns a
directory for archive and multipart packages. `files` lists the relative paths
inside each directory. The UI must not infer installation from file presence.

## One device store

The pre-existing Index model stays at
`getExternalFilesDir(null)/Index-Translate-9B.Q4_K_M.gguf`.
Other installed files and directories live under `packages/` on that same volume.
There is one package per shared voice, regardless of how many languages use it.
Token files, weights, licenses and auxiliary files belong to the parent package.
Deleting a package deletes all of its components.

Downloads are serialized, with a process/file lock protecting storage ownership.
The app checks remaining compressed bytes, expanded installation bytes and a
128 MiB reserve before beginning. Partial files and HTTP ETags survive process
death. A subsequent start resumes with HTTP Range/If-Range; a server returning
200 instead of 206 restarts that component safely. Network failures retry twice.
Only HTTPS, bounded redirects, exact response ranges and sizes are accepted.

Pause preserves partial files; cancel deletes partial files. Both interrupt
network and verification work. Resume can replace a paused operation even while
its socket is unwinding; the serial executor waits for cleanup before restarting.
Downloads/imports use a `dataSync` foreground service, with progress notifications,
pause/cancel actions and a bounded wake lock. Completion is reported only after
verification. The UI and service never open a second store lock. Android 15+
timeout pauses work and stops the service immediately. Process termination leaves
partials resumable by a later explicit user action; the service is NOT_STICKY.

## Language setup and queues

`PackageLanguageSetup(primaryId, targetIds, recognition, speech).plan(...)` resolves
the selected translation model, Whisper/Omnilingual capabilities and selected voice
per language. OPUS Big is the Android default (user decision after Pixel validation,
2026-10-12); an existing explicit selection is preserved. OPUS requires an available runtime and
English-centric directions. Unsupported ASR/TTS languages are returned separately
for UI disclosure; shared multilingual packages are deduplicated.
`PackageSetupPlan.summary(states)` reports total/remaining bytes, verified readiness,
active work and failures. `withActivePair` includes later language selections.
`PackageVoiceDownloads.plan` selects one voice for every supported language and
deduplicates shared weights for the download-all-voices action.
The Android setup screen preserves the user's selected translation model, including
Index for Russian/English; it never automatically switches to OPUS when applying
setup. A fresh installation uses OPUS; choosing an unsupported language pair reports
that limitation instead of silently switching engines. Index remains available with
its existing verified weights and path. In portability-contract.json, primary_translation
identifies the original Index portability/weight contract; default_translation is the
current Android product default. These are intentionally separate.

`PackageDownloads.startAll(context, ids)` submits one service command after a
conservative aggregate disk preflight; each package checks space again before
installation. `pauseAll` preserves the queue's partials; `cancelAll` also removes
partials for paused packages. Restarting the same explicit plan resumes it.

`DownloadAccess` persists `allowCellularDownloads` (false by default), matching
Apple's setting. The UI can inspect `networkState`, `requiresConfirmation`,
`canDownload` and the repository's `maximumDownloadBytes(ids)` before showing the
same download confirmation. This byte figure is an upper bound, because a server
can reject Range and resend a part. Fully cached/installed packages and imports
do not need a network permission prompt.

Each operation snapshots the preference. Every new connection checks the active
network and uses Android's [Network.openConnection](https://developer.android.com/reference/android/net/Network#openConnection(java.net.URL))
to bind that connection, without changing the app's global routing. The read loop
also checks policy, including a VPN's changed underlying cost. Metered Wi-Fi and
unknown-cost transports require permission; an explicitly unmetered Wi-Fi or
Ethernet transport is allowed, including a VPN reporting those capabilities.
Offline/unknown network state cannot be overridden by the cellular toggle.
Changing the preference applies to the next operation, as on Apple.

Every downloaded/imported component is checked against its pinned size and
SHA-256. Multipart imports accept one component at a time and finish once every
component is present. Unknown files are rejected. Piper metadata preparation
uses the shared metadata suffix/tokens, then verifies the derived files against
the shared installed manifest.

Archive installation permits only manifest-listed ordinary files and directories.
Absolute/traversal paths, symbolic links, hard links, extended headers, duplicate
files, unknown files, excess bytes and bad checksums are rejected. Extraction is
bounded by manifest lengths and 2048 archive entries; the bzip2 checksum/footer
is consumed before publication. Verified data is atomically renamed on the same
volume; receipts are written after successful installation. Existing installations
are rehashed when their identity or file stamps change.

## Platform constraints

The current Android media runtime can use Whisper, Sherpa Piper/MMS, Supertonic,
Omnilingual and the ONNX OCR models. Shared Core ML Parakeet weights require Apple
Core ML; catalog display explicitly directs Android users to Whisper. Wayu and
OPUS-MT are enabled following the Pixel build7b acceptance run:
`.build/android-parity-device/opus-wayu-build7b/attempt-1.log` reports two passing tests.
OPUS checked 12 file hashes, 8 Apple token fixtures, 6 directions, limits,
cancellation/new-request and reload. Wayu synthesized 27,000 nonzero samples at
24 kHz in 6.12 seconds. OmniVoice remains unavailable pending device acceptance.
Package installation is never presented as
proof that an unavailable engine works.

## Validation

`PackageSafetyTest` exercises real local HTTP transfer interruption, resumption,
ignored/invalid ranges, pause, pinned digest/length verification, archive traversal,
link, duplicate and unknown-file rejection, and full shared-catalog loading.
Run `:app:testDebugUnitTest --tests '*PackageSafetyTest'` plus the metadata generator
check. Device playback/recognition/OCR and lifecycle testing are separate integration
checks; successful package installation alone does not establish inference parity.

`PackageLanguageSetupTest` covers shared-model deduplication, optional capabilities,
OPUS constraints, voice fallback, missing capabilities, partial/verified progress,
and extending the active language pair. `PackageDownloadServiceTest` requires an
already installed OCR package (`servicePackageId=ppocr-v5-english` by default) and
notifications already enabled. It never grants/revokes permissions. If necessary,
the host harness must snapshot/grant/run/restore notification permission externally
because revocation can kill instrumentation. Its cached-file lifecycle test does
not replace device tests of active network pause, background transfer or timeout.

`PackageRepositoryLifecycleTest` has four isolated device cases. Its internal
constructor supplies a disposable cache directory, two pinned synthetic files
(768 KiB total), and a per-instance controlled HTTPS connection. It never changes
the singleton, system transport/security policy, permissions or user model files.
The cases exercise a blocked read followed by immediate pause/resume, queued
pause/resume, exact Range/ETag, lease-protected deletion, cancel/restart at zero,
closing/reopening with a partial, rejecting a modified installed file, and recovery
from a failed digest. Only the connection is substituted; repository disk writes,
checksums, receipts, atomic publication and operation cleanup are real. This is a
repository lifecycle test, not proof of Android foreground-service lifecycle.

`DownloadAccessTest` checks the network decision matrix and interrupts a real
partial-file transfer when the fixture changes to cellular, then resumes the
same bytes after Wi-Fi returns. No global cleartext/TLS exception is configured.

## Automatic OCR selection (Android)

Apple automatic OCR uses Vision language detection; its open PP-OCR fallback accepts
an explicit Russian or English source. Android has no Vision. Automatic OCR now runs
all installed official English/Eslav recognizers on identical detector crops, with
one detector pass and one recognizer in memory at a time. It never selects by catalog
order, changes the translation engine, downloads weights, or labels the source language
from a recognizer ID. One installed recognizer still works, with a visible coverage
notice. Coverage is limited to these OCR packages, not all Index translation languages.

CTC confidence averages emitted nonblank tokens (not blank padding or duplicate time
steps). Different candidate strings require confidence >= 0.85, a >= 0.12 lead, and
at least three alphanumeric characters. A documented deletion exception handles a
wrong-script recognizer dropping unsupported glyphs: the higher-confidence candidate
must score >= 0.90, contain at least four alphanumeric characters and at least two
more than its rival, while the rival retains at most 75% of its characters and has
at least 25% greater residual uncertainty (1 - mean confidence). Length alone cannot
win. Otherwise the user must choose an explicit source or a clearer image. Case-only
differences count as agreement; Cyrillic/Latin lookalikes remain distinct. Agreeing strings and a single installed recognizer still
require the confidence floor. Scores across models are not calibrated language
probabilities: this conservative heuristic can reject correct text, and confident
OCR mistakes remain possible. Pixel build15 correctly recognized seven generated
fixtures; this is limited fixture evidence, not general recognition accuracy. Unsupported scripts cannot
be automatically identified reliably with these two weights.

The confidence adapter is Android-only (`ocr_scored.c` includes the shared runtime),
so the Apple native OCR source and its existing API remain unchanged. Explicit-source
OCR continues using its original CTC path. Ambiguous blocks fail the complete operation
rather than silently losing text. `OcrAutoSelectionTest` covers English/Cyrillic wins,
mixed-script boxes, catalog-order independence, conflicting high confidence, short
homographs, low confidence, numbers, single-model coverage, and CTC blank/repeat scoring.

Pixel build14 established an auto-OCR regression: Cyrillic `ПРИВЕТ МИР` scored
0.9394511 while the English model emitted shortened `PBET MP` at 0.89183354. The
original absolute-margin-only policy rejected this correct result. The deletion
exception adds independent content coverage evidence rather than lowering the margin
for all competing strings. These remain heuristic thresholds, not calibrated language
probabilities. The exact observation and near-tie/longer-noise counterexamples are
unit-tested. Pixel build15 correctly recognized seven single/dual/mixed, serif
lowercase and English monospace fixtures. Cyrillic monospace `Встреча завтра`
remained ambiguous: English emitted `Bctpeua 3abtpa` at 0.8990104; Eslav emitted
the correct text at 0.88896984. Evidence: `.build/android-parity-device/default-ocr-build15.log`.
This is a supported explicit-source fallback, not a claim that automatic recognition
works for every font. Production thresholds were preserved. The device contract now
separates seven accurate-auto fixtures from a test requiring `Ambiguous` for that
monospace image and correct Eslav output when the source is chosen explicitly. The
new explicit-fallback device assertion awaits the root build16 run.
