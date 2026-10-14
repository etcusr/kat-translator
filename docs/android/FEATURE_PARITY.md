# Android product parity audit — historical baseline, 12 October 2026

> Матрица накоплена на ранних этапах 0.3.x. Текущий выпуск 0.4.5/code20 и поздние изменения моделей, Auto, ASR/OCR и UI описаны в [CURRENT_STATE](../CURRENT_STATE.md). Верхние строки о выборе MT/ASR уточнены по коду 13.10; остальные результаты, числа тестов и pending относятся к своим прогонам.

This inventory records the iOS/Android comparison at the time of the audit, with selected routing rows updated below. Implementation presence is not device acceptance; no complete parity claim is made.

Sources reviewed: shared/apple/Conversation, Audio, Speech, History, Models,
Settings, Diagnostics; apps/ios/Camera; OfflineCore.TextSegments; docs/CURRENT_STATE.md.

Latest loading/audio corrections and acceptance: [0.3.3 report](benchmarks/2026-10-12-loading-audio/README.md).

| Current iOS behavior | Android implementation / status |
|---|---|
| Voice / Text / Camera, black/lime design | Compose workspaces; independently retained source/result per mode |
| Models list and modal gestures | Fixed bounded rounded overlay in the same app window, fixed header, one LazyColumn; no draggable sheet or nested gesture ownership. Large title/Done presentation follows current iOS. Build7b exposed merged semantics in the touch shield; corrected for build8. Root WorkspaceNavigationTest passed all three cases: real alternating swipes with stable screen coordinates, IME navigation and landscape voice access |
| IME / navigation | Explicit clearFocus + hide; no wait on stale IME inset and no secondary window. Full text workspace scrolls. Same-window navigation/reader accessibility correction accepted by root build8 navigation suite |
| Index 9B offline translation | Existing exact shared model preserved; root integrates native MTP, switch defaults on for Vulkan |
| Long input segmentation | Sentence/word-preferred recursive split based on exact prompt/source tokenizer counts; progress and cancellation, no truncation |
| 150 languages / search / favorites | Shared list, model-filtered languages, RU/EN/code search, separate favorite/all groups, capability legend, recognition/selected-voice status and limitations; latest picker, favorites/search and nested navigation passed build10b UI sweep |
| Automatic source language | Current Android voice/camera require an explicit language; text detection remains. Earlier voice-detection results below are historical |
| RU / EN / system interface | Current shared Apple catalog English strings plus Android-specific explicit translations; manual review pending |
| Record hold / toggle, pause, duration, silence | AudioRecord 16 kHz, pause excludes duration, Silero VAD, configurable 1–30 s silence and 1–30 min limit; cancel recording on background, matching current AppModel lifecycle. Root RecordingControlsTest passed on installed build13 |
| Imported audio | Android MediaExtractor/MediaCodec streaming decode/downmix/resample via private PCM spool to bound Java heap; 30 min resource bound; generated wave/packet/cancellation and full import tests passed on Pixel |
| Offline ASR -> Index -> offline speech | Worker serialization and unload boundaries; root VoiceImportFlowTest passed shared PCM import → Whisper → Index → Supertonic and original/translated WAV exports in build9 |
| Recognition selection | Current Auto: RU → GigaAM v3; other supported Parakeet languages → Parakeet TDT v3, with missing-package prompt. Manual selection overrides Auto. Other on-device/Whisper/Meta routes remain; system recorded-audio path requires Android13+ and has no cloud fallback |
| ASR during recording / verified provisional transcript | Implemented bounded 30-second snapshots, minimum 2-second phrase plus 1-second silence, serialized ASR/translation, provisional phrase commits and optional full verification after stop. Whisper+Index only, disabled in memory saving/high thermal state; native phrase-ledger contract passed, combined microphone/ticker-to-native dispatch remains unverified |
| Per-language voice choice | Catalog selection persisted, Piper/MMS/Supertonic/Wayu/OmniVoice connected to offline native backends; selective real Piper, Supertonic, Wayu and OmniVoice synthesis passed; full MMS/language quality coverage pending |
| Voice previews / sample selection | Exact shared bundled preview per language/model, only offered when sample file exists; 12 Wayu voice choices |
| Speed / pause / stop / original playback | AudioTrack controls, exact 1/1.25/1.5/2 speed options with live rate change, pause-preserving; same-audio button stops playback. SpeechLoudness normalization for original and synthesized audio; ASR samples unchanged |
| Share original / completed translated audio | Voice-panel icons only; original recorded PCM with iOS loudness normalization, target completed TTS WAV. No extra bottom share buttons or source TTS; text mode shares text. Chooser payload tests intercept sharing; no external recipients. |
| Camera / gallery / crop / OCR -> translation | In-app Camera2 preview/capture and gallery; bundled ML Kit for supported scripts; PP-OCRv5 mobile detector + shared eslav recognizer for Russian; explicit source language; paragraph grouping, per-block offline translation and image overlay. Core controls now follow current iOS camera; helper/lifecycle instrumentation passed build7b. Root FrozenPhotoFlowTest passed build13: generated HELLO WORLD → real OCR → Index Russian, UI target change → German reprocessing of the same image, rendered private PNG export |
| Live camera preview recognition | Implemented bounded YUV frame single-flight delivery, scene-change cancellation, cached block translations, lifecycle/revision checks, focus and 1×/2× zoom. Camera preview test in root build7b; newest layout pending |
| OCR automatic source | Automatic routing evaluates installed English/Cyrillic recognizers, states installed coverage and rejects ambiguous results; seven font/script cases plus ambiguous/manual retry passed build16 |
| Camera rotate / perspective / overlay quality | Upright normalized rectangles with shared paragraph grouping. Perspective/crop helpers exist but are not primary controls in current iOS UI. Frozen image pinch 1–5×/pan/double tap implemented; exact overlay typography/rotated polygons remain a visual limitation |
| Image sharing / history | Rendered PNG share, explicit MediaStore gallery save, frozen text sheet with copy/clear; independent retention. Android photo-save permission flow differs naturally from Photos |
| Text history / reader / copy / share | Persisted iOS-style chronological sections with full selectable text/copy and independent media actions. Main text reader has live copy/count and preserves playback when closed |
| Audio / image history limits | Separate count/days pruning; 0 means unlimited. Audio files counted individually, including original recordings saved on ASR/translation failure; independent switches. Retention draft preserved through nested navigation, committed on Done or explicit save |
| History audio playback | In-app MediaPlayer playback; image thumbnail and internal pinch/zoom reader compiled; history uses a LazyColumn and reader returns to its history owner |
| Download / verify / import / pause / cancel / remove | PackageRepository uses shared catalog, progress UI; process singleton shared with download service, explicit import/download actions only; package-agent validation applies |
| Background download notifications / iOS Live Activity | dataSync foreground service, explicit Download permission prompt, visible main-thread handoff. Root PackageLifecycle tests passed build7b. Shared language setup plan, deduplicated batch downloads, cellular/metered consent enforced on bound network. Live Activity is Apple-only |
| Memory saving / auto-load / unload | Auto-load default true, skipped in memory saving; Index released before media/after work in memory-saving mode. Settings order/labels/menu choices follow current iOS sources |
| Resource diagnostics / export | Timing, RAM/storage, device/runtime/MTP report without source text; share as text |
| Privacy | No remote inference; explicit model download is network use; FileProvider only scoped exports/camera/history |
| Apple widget / App Intents / Apple audio sessions | Platform-specific, not binary-portable; Android native alternatives assessed separately |
| Default / alternate translation | Current initial selection is Auto, preserving saved manual choices: strong device → installed 9B/2B; other devices → supported installed OPUS/2B/9B. Index 2B uses Vulkan without MTP; 9B uses Vulkan/MTP. OPUS includes the legacy EN package and catalog directions. Earlier build17 default-selection tests describe the former OPUS default |

## Validation evidence

- Root reports installed build13 RecordingControlsTest and FrozenPhotoFlowTest
  passed. The photo test uses only generated HELLO WORLD pixels: actual OCR and
  Index translation to Russian, the real language picker to German, automatic
  reprocessing of the same bitmap, and a private PNG with rendered translation.
  No private camera image or public-gallery file is used. The combined batch
  was 2/3 because the default-model test attempted to scroll a fixed button;
  root corrected that test for the next build.
- RecordingPreviewRuntimeContractTest passed on Pixel (`preview-build13.log`,
  281.629 s): bounded native snapshot, one committed phrase, actual full Whisper
  verification and cancellation publication rules. This does not claim combined
  AudioRecord/ticker dispatch acceptance.
- Rounded modal corners are visible below the status bar in build14 screenshots;
  unchanged header coordinates and repeated-swipe navigation passed build16/17.
- AutoOcrDeviceTest passed build16: seven English/Cyrillic/mixed/font cases plus
  intentionally ambiguous monospace rejection and successful explicit-source retry.
- Build18 hold regressions passed real DOWN/MOVE/UP, ACTION_CANCEL and workspace
  disposal. Whisper cancellation required an Android-only scheduler callback fix:
  the real Cancel control returns idle in 628 ms and a subsequent OPUS request
  succeeds (`platform-asr-cancel.log`). Holding across the configured silence
  threshold also passed build19; silence auto-submit remains active only in tap mode.
- Native platform speech probe confirms Pixel's system on-device service and
  installed ru-RU/en-US models. Actual supplied-audio RU/EN, auto with complete replay, cancellation/reuse and product ASR→OPUS flow passed builds19/20. See research/platform-speech.md for timings and limits.

- Latest complete root checkpoint: `.build/android-parity-build10b.log`:
  native/Kotlin compilation, JVM tests (including six SheetNavigation contracts),
  lint and APK assembly passed in 1 minute 4 seconds.
- Installed build10b UI suite passed **8/8 tests** in 30.904 seconds:
  `.build/android-parity-device/ui-build10b.log`. This includes WorkspaceNavigation,
  ProductInteraction, SettingsParity and MenuNavigation. The build10b settings
  screenshot visibly confirms the thin neutral slider track, white thumb and
  corrected modal top inset. This result supersedes the earlier build8 test-only
  lazy-row assertion failure.
- Root build8 WorkspaceNavigationTest: 3/3 passed. Real wall-clock alternating
  swipes moved list content while screen-coordinate header/window bounds stayed
  fixed. IME navigation and landscape voice-control reachability passed.
- Root build8 SettingsParityTest passed picker/record controls, conditional
  verification, retained draft through Back and history sections. Its screenshots
  exposed Material slider styling and excess modal top padding; build10b replaces
  the track/thumb while preserving native accessible Slider semantics, and
  subtracts the sheet's existing top offset from required safe insets.
- Root ProductInteractionTest build8: 2/3 passed. The remaining Japanese-row
  assertion required scrolling its lazy list; root corrected the test before
  the final sweep; the corrected build10b suite passed all three ProductInteraction
  tests.
- Root build9 VoiceImportFlowTest: 2/2 passed in 120 seconds, including the full
  shared PCM → Whisper → Index → Supertonic path and both WAV exports. Earlier
  thermal-guard force-stops were not native crashes or acceptance passes.
- Root reports build7b launcher icon, Wayu and PackageLifecycle tests: 9 passed;
  camera lifecycle/pixels: 4 passed; download service: 1 passed; SpeechPlayback:
  2 passed. These establish their named contracts, not every interaction.
- Latest navigation audit covers all sheet routes: modal owners, stepwise Back,
  owner-level Done, full-screen image-reader return, preview/history-only cleanup,
  saved search/scroll during nested navigation and reset after owner dismissal.
  Frozen camera language changes now invalidate old text and reprocess the image.
  Gallery save publishes an explicit confirmation in `camera.status`.
- RecordingPreview pure tests cover phrase boundaries, no overlap, cancellation,
  30-second bounds and preservation; media retention tests cover per-file limits,
  unlimited count and age independently. The real bounded-snapshot ledger → Whisper → Index → full Whisper verification
  contract passed in `preview-build13.log` (281.629 s); microphone/ticker-to-native
  dispatch together is not yet accepted.
- No claim of identical pixels or complete parity is made. Remaining platform
  differences include Apple CoreML Parakeet Ultra, Apple Vision and Apple widget/
  App Intents APIs. End-to-end microphone/ticker preview
  acceptance and full language/voice quality coverage remain unverified.
  Verified-sentence reuse/prepared-speech optimization is deferred by user priority.
- Root exclusively owns installations and device workloads. The user's latest
  steering removed the thermal gate for subsequent functional acceptance tests.
