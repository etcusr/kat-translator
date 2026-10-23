# Interface captures — 22 October 2026

**23 October presentation addition:** eight prepared Voice/Image scenes added with owner approval; 32 iOS + 16 Mac images now. Four presentation UI tests passed. These scenes use a separate simulator-only source snapshot, not actual ASR/MT or camera capture. [Evidence and reproduction](../ios-presentation-scenes-2026-10-23.md). Include `--ios-presentation <attachments>` when collecting the complete set.

**Refresh, 23 October:** the 24 iOS images were recaptured after the adaptive language-row fix. Three Mac previews per language have now been replaced by full-window Voice/Text/language-picker screenshots with diagnostics off; the fourth Quick setup preview remains. [Mac capture method/results](../mac-window-captures-2026-10-23.md). Use `--mac-windows <final-xcresult-attachments>` in the collector to reproduce this selection. The manifest records current bytes/hashes. Existing iOS73/directMac68 exports predate the UI fix; Store79 includes it. The details below describe the historical 22 October run.

24 simulator screenshots: `python3 scripts/simulator/run.py --screenshots --headless`, exact iPhone 17 Pro / iOS 27.0, development app 1.1.0 (73). Four tests passed, zero failures/skips. Same neutral Russian directions question, actually translated to English by Index 2B CPU. EN/RU/ES/TR interface. No downloads, live audio or fabricated result fields. Status bar is the actual capture state, not composited.

16 Mac previews: opt-in `PublicationPreviewTests` with `TEST_RUNNER_KAT_PUBLICATION_PREVIEW_DIR`; own NSHostingView cached to PNG, no desktop capture. One test passed, zero skips/failures after correcting test-runner environment propagation and using the actual Settings navigation for Voices. Earlier skipped run is not acceptance. Volatile launch defaults restored; no inference, model deletion or settings interaction. No full-screen/window screenshot claim.

Collector: `scripts/publication/collect-interface-captures.py --ios <xcresult-exported-attachments> --mac <preview-root> --date 2026-10-22`. It copies PNG bytes unchanged, excludes raw XCTest device identifiers and writes dimensions, hashes, version and capture method. 40 PNG files total, 5,761,927 bytes. Mac preview sizes are not Store sizes.

Visual inspection covered representative iOS text/settings and Mac settings/models/voices states, including localized labels. Full matrix is available for owner review; no claim of exhaustive pixel-level inspection. Browser checks exercised all eight platform/language gallery selections. Android was not connected. iPad, Voice/Image scenes, full Mac captures and real-device demo remain pending.

Memory constraint added after owner reported concurrent native Kat/simulator memory exhaustion: run each platform separately and shut down the simulator before Mac work. Do not repeat simultaneous inference to reproduce it. The dedicated simulator is left shut down; all seeded model clones and Duo are retained.
