# iPhone presentation scenes — 23 October 2026

**Selection update, 23 October:** the four iPhone Image screenshots were subsequently removed at the owner’s request. The active gallery now has 28 iPhone screenshots (four prepared Voice examples) and 16 Mac entries. The selected Store folder is `dist/store/apple-1.1.0-preparation-2026-10-23-selected/`, with 28 iPhone + 12 Mac images. Counts and checks below describe the original capture run.

## Result

Added eight 1206 × 2622 screenshots: Voice and Image in EN/RU/ES/TR. The gallery now contains **32 iPhone images, 12 full Mac window images and four Mac Quick setup view previews**: 48 PNGs / 8,582,886 bytes. The local Store-copy folder includes 32 iPhone and 12 Mac images; Quick setup previews are excluded.

These eight new scenes use prepared original/translation text, prepared for presentation. The real SwiftUI screens render the state in a separate simulator-only source snapshot. No screenshot pixels were composited or edited. The examples are a hotel-room request and a breakfast/reception sign. They do **not** demonstrate ASR, translation quality/speed, microphone/camera capture or audio playback. Enabled result controls in the fixture do not establish their functionality. Existing 24 iPhone captures and 12 full Mac captures retain their previously recorded actual-inference provenance.

## Isolation and reproduction

[`scripts/publication/ios-presentation`](../../scripts/publication/ios-presentation/README.md) contains the snapshot preparation script, four-locale capture test and bilingual instructions. The snapshot was based on `1eea583`; only its AppModel, ConversationPipeline, ImageTranslationSession and CameraModel state was patched. A compile-time guard in the copied app entry point rejects physical-device builds. No shipping source, model catalog, runtime or version changed. Dependencies are reused read-only; models are not loaded for these scenes.

Local evidence: `.build/publication-followup-2026-10-23/` contains the source snapshot, provenance, build logs, `scenes.xcresult`, summary and exported attachments. The reproducible script generated five patched files byte-identical to those compiled. Earlier import-picker probes and two fixture build failures are preparation attempts, not app-regression evidence or successful tests.

After capture the ordinary simulator build was reinstalled over the presentation app without deleting its container. The restored executable and Info.plist SHA-256 match the ordinary simulator build. The dedicated simulator is shut down. Native Mac Kat was not run concurrently; physical iPhone/Mac apps were not installed or changed. No Store, review or push action occurred.

## Checks

- Isolated Debug simulator build succeeded.
- Four capture tests passed, zero failures/skips; eight named screenshots exported.
- All 48 manifest hashes, byte counts and dimensions verified. The assembled 32 + 12 Store images match their manifest entries.
- Four iPhone gallery language selections each show eight images, including two labelled prepared examples. Russian Voice/Image frames were inspected at full view; no claim of exhaustive pixel review for all languages.
- Independent read-only review found no important issues in isolation, provenance or packaging; the screenshot manifest is also carried with the assembled folder.
- Documentation parity and simulator memory guard: four tests passed. Changed Python scripts compile; whitespace check passed.
- Exported iOS 1.1.0 (73) IPA and current target declare `UIDeviceFamily = [1]` / iPhone only. Native iPad presentation is outside this candidate; iPad compatibility behavior was not retested.

The updated local assembly is `dist/store/apple-1.1.0-preparation-2026-10-23-scenes-final/`. The release checklist remains open for Android captures, real-device video, candidate upgrade acceptance, refreshing packages that predate the language-row fix, landing-page redesign, and separately authorized Store/publication steps. These presentation fixtures do not close functional acceptance items.
