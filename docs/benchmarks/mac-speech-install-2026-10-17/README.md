# Corrected Mac speech installation — 17 October 2026

The corrected Apple streaming speech implementation was built in Release configuration and installed at `/Applications/Kat translator.app`, replacing the older local application. The installed development version remains **0.6.7 (60)**, bundle `org.openoffline.translator.mac`, source fingerprint **mac-c075be03543c17ac**. At this installation step the earlier DMG/ZIP and Mac App Store build70 were not replaced. The modern DMG/ZIP were subsequently [refreshed and verified](packages.md); App Store70 remains unchanged.

## Fresh validation

- Release app and runtime-test build passed.
- Four packaged Mac tests passed: MLX partial output/cancellation/reuse; default MLX → real Irina before translation completes; complete long sentences, whitespace and ordinal fixtures; actual audio-player pause/resume/speed/stop. The streamed pipeline tests capture scheduled PCM; the separate player test uses real playback. They do not constitute an acoustic recording of streamed output.
- OfflineCore: 288 tests, 2 opt-in skips, no failures. MLX Python/C bridge: 9 tests passed. Documentation parity: 2 tests passed.
- The standalone candidate excludes XCTest bundles and is signed with the same existing development identity as the prior installation. Deep/strict signature validation passed.
- Bundle audit: 161 Mach-O files, no non-system external dependencies or external RPATHs, no component requiring a newer OS than the declared macOS27 minimum.
- Installed executable, Index Python engine and translation runtime hashes matched the verified candidate. The installed application opened normally and remained running. Its source fingerprint is available in `BuildIdentity.plist`.

The installation changes the application bundle; model packages and saved settings are not moved. No rollback copy from this installation is retained. This is a direct development installation, not a notarized distribution or App Store upload. The [earlier Mac correctness report](../apple-speech-correctness-2026-10-17/README.md) and [iPhone acceptance](../iphone-speech-correctness-2026-10-17/README.md) provide additional scoped evidence.

## Reconciled runtime decisions

The completed [iPhone MTP/KV comparison](../ios-mt-options-2026-10-17/README.md) retains current MTP2 settings. Experimental switches are absent from current source. Smaller weight formats and an iPhone MLX port have not been implemented. Android Whisper Q8 is already available and verified separately; the earlier note that it was untested is superseded by the [Pixel comparison](../../android/benchmarks/2026-10-17-whisper-options/README.md). Android ordinal normalization and sentence streaming remain separate, unimplemented work.

Public history contains the finished source changes and sanitized reports. Models, application bundles, private recordings, device identifiers, signing material, raw logs and local handoff journals remain outside Git.
