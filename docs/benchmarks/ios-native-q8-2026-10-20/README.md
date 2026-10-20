# Native Whisper Q8 in main iOS — 20 October 2026

Development version 1.0.1 (58) selects Whisper large-v3-turbo Q8_0 on iOS. macOS and Android retain their previous F16 asset. This is a catalog change using the existing native Metal backend; the production Whisper archive is unchanged and Core ML is disabled for Whisper.

## Model and first launch

The initial language setup selects Q8 for languages supported by Whisper, using the same catalog as Models and runtime preparation. It displays **Whisper large-v3-turbo · Q8**, **874.2 MB**. Other recognizers remain available for their supported languages.

| Asset | Bytes | SHA-256 |
|---|---:|---|
| iOS Q8_0 | 874188075 | `317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1` |
| Preserved F16 | 1624555275 | `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69` |

Both downloads are pinned to upstream whisper.cpp model revision `5359861c739e955e79d9a303bcbc70fb988958b1`. Q8 has its own model ID, background-session ID and transfer directory. Existing F16 download callbacks retain the original F16 descriptor; a completed F16 transfer cannot mark Q8 verified. Old F16 weights are not deleted automatically. An existing installation therefore needs an additional Q8 download and temporarily retains both files.

## Diagnostic file import

With technical information enabled in Settings, Voice shows **Open audio file**. It uses the system Files picker, scoped file access and the existing bounded audio decoder, then runs normal recognition and translation. Automatic speech follows the saved switch. The main app's Documents directory is not exposed through file sharing. iOS prepares recognition again after a completed file cycle when needed.

## Verification

- Catalog regression first failed with F16 selected for iOS, then passed with Q8.
- OfflineCore: 346 tests, 3 skipped, 0 failures. Includes independent download identities and retention across an application-container relocation.
- Project validation: 153 tests passed. Android portability still verifies the unchanged F16 descriptor.
- Release build-for-testing and deep signature verification passed. Signed increased-memory-limit entitlement is present; app and widget versions both 1.0.1 (58).
- Production Mac/iOS native Whisper archives and source F16 weights match their pre-experiment SHA-256 values.
- Physical iPhone 17 Pro: in-place development update 57 → 58 passed. The real setup screen showed Q8 and 874.2 MB; the normal downloader downloaded and verified the asset. Four silent Files-picker cycles matched the lab Q8 recognition and translation strings exactly, with no synthesized audio. Turning diagnostics off hid the import action and left recording ready after relaunch. UI acceptance passed in 208.672 seconds.
- Final device rerun passed in 106.726 seconds, including date correction enabled by default and the 3-second silence setting. The initial UI assertion searched for a standalone value; iOS exposes the combined row label. Correcting the test locator resolved the failure without changing the application.
- All 770 pre-existing model/voice files remain. 753 are byte-identical, including every weight and receipt; 17 verification-cache files differ only in filesystem change-time fields after in-place installation. Q8 adds three files and its downloaded weight SHA-256 matches the catalog. The original nine history records and six audio files remain exact; twelve silent test records were added. Final user preferences match the snapshot; only operational Live Activity download IDs changed. Recognition selection is restored to Auto.

The setup screen is checked on the upgraded installation; no app/container deletion is used to simulate a clean first launch. Imported audio is not a live-microphone test. Speech playback remains disabled during this acceptance run. Earlier lab comparisons, including full spoken cycles and the existing date-recognition limitation, are documented in [the lab report](../ios-coreml-voice-cycle-2026-10-20/README.md). Q8 itself does not fix the raw date-recognition bug. At the owner's request, the final iOS build enables the existing date/time repair by default and changes default silence timeout to 3 seconds. Saved explicit values remain authoritative; macOS/Android defaults are unchanged. The matched-Q8 comparison explicitly disables repair to preserve the previous benchmark conditions; a subsequent launch without that override checks the new Settings defaults.

The device checks use a development build. Distribution packaging and submission are tracked in [the release report](../../publication/ios-q8-store-2026-10-20.md); this is not a TestFlight installation test.
