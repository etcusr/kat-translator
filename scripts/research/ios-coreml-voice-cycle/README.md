# Separate iPhone voice-cycle lab

**English** | [Русский](README.ru.md)

This experiment builds a frozen committed Kat source snapshot under `.build`, with the independent bundle `app.kattranslator.voicelab` and name **Kat Voice Lab**. It must never replace Kat or write into Kat's container. Uncommitted work in the primary checkout is excluded.

The application retains its recorder, recording preview/verification, Index 9B translation, streaming speech synthesis, player and memory-pressure handling. Only the ASR model/runtime, lab identity/defaults and diagnostic hooks differ. Memory saving is off, Whisper date/time repair is off, RU→EN is explicit, Lessac is selected for English speech. The Core ML encoder is FP16; the complete native model file is Q8.

## Preparation

1. Create an empty `.build/<experiment>/source` with `git archive <commit>`. Record the commit. Include `apps`, `shared`, `assets`, `scripts`, `docs`, `tests/fixtures` and `PROJECT_DESCRIPTION.md`. Link `Dependencies` read-only in practice to the existing build outputs, and supply a local signing configuration. Do not copy private data or Git history.
2. Run `prepare.py <snapshot> --native-build <isolated-whisper-ios-build>` once. It asserts that replacements match the frozen source. Use the native build and model files from the [earlier isolated Whisper experiment](../apple-whisper-acceleration/README.md).
   For diagnostic file input, then run `enable_file_import.py <snapshot>` once, before building.
3. Build the generated iOS project for testing in a separate DerivedData directory. Supply the developer team locally. Verify the lab bundle ID, increased-memory entitlement and signature.
4. Run `provision.py` with the device, work directory, local model-store downloads and research Whisper models. It installs only the lab and copies Q8, the compiled encoder, Index 9B, Irina/Lessac archives, receipts and the F16 control into its own container. Normal app model verification remains enabled.

The lab catalog uses an explicit Q8 lab ID and checksum, with an invalid download URL: these are locally provisioned research assets. A requested Core ML load failure aborts the experiment; silent Metal fallback is forbidden. The F16 control explicitly disables Core ML and uses its separate local file.

## Acoustic test

Use file input below for routine comparisons. Acoustic playback is a separate microphone check and interrupts Mac listening; do not run it as the default benchmark.

Use `run.py --device ... --work ... --name <fresh-name> --short <audio> --long <audio> --capture-output`, optionally `--baseline`. Keep the unlocked iPhone near the Mac's speakers. The test taps the real microphone, grants the lab microphone permission, records three short phrases and one longer phrase, waits for translated audio playback, then checks another capture. The host plays external acoustic stimuli; no audio is imported into the application. Optional Mac microphone capture provides independent output evidence. Record the provenance of both stimuli. Four `--date-input` arguments select the additional date block: original problem case, time-before-date control, date-before-time control and repeated long clip. For audibility, that block uses external stimuli normalized with `loudnorm=I=-18:TP=-2:LRA=11`; application capture and recognition are unchanged.

`ResearchTrace.swift` samples physical footprint, the process lifetime footprint maximum, resident memory, the iOS allocation headroom and thermal category every 100 ms. It also marks capture, ASR load/inference/unload, memory warnings and playback completion. Final cycle telemetry and private transcripts are saved locally. Existing TTS diagnostics supplement these samples. The baseline override is identified by the launch trace; its pipeline catalog label still names the lab Q8 descriptor, so do not infer the actual weights from that metric alone.

Check all completed cycles, correct source/target content, nonempty generated audio, real playback completions and repeated capture. Compare cold and repeated use; inspect memory warnings, ASR reloading and thermal state. Acoustic input can differ between runs, so these timings are not a controlled identical-PCM speed benchmark. Allocation headroom is not total free system RAM, and process footprint excludes external Core ML services.

All audio, transcripts, raw logs, signed builds, signing/device identifiers and model weights remain outside Git. Publish only sanitized aggregate evidence. Verify the primary app inventory/preferences afterward. Do not upload or submit this lab to the Store.

## File input without Mac playback

The optional patch enables the existing Mac `AudioFileImport` / `AppModel.importAudioFile` path in the disposable iOS snapshot. When technical information is enabled, **Recognize audio file** appears below the microphone, with a diagnostic file-input label. The system picker reads local Files/iCloud URLs with security-scoped access. Existing duration limits, format decoding and cancellation are retained. It never imports into the primary app. File input bypasses recording/VAD/recording previews and is identified by `inputMode: audio-file`; it must not be reported as microphone acceptance.

This lab exposes its own Documents folder in Files. Copy the four stimuli to `Documents/AudioTests` with basenames `01-date.wav`, `02-time-first.wav`, `03-date-first.wav`, `04-long.wav`. Do not put secrets in that lab folder. No amplitude normalization is required for this block. The trace hashes the actual decoded mono 16 kHz PCM, so equal input across variants can be verified.

Run `run_files.py --device ... --work ... --name files-<variant> --variant <variant> --repeats 2`, sequentially for `f16`, `q8`, `coreml-q8`. The UI selects files; ASR and Index 9B translation execute on iPhone. Automatic speech is off by default in the lab and file tests; `--speak` opts into an explicitly requested iPhone playback check. This runner performs no Mac playback or recording. `q8` explicitly disables Core ML and uses native Q8; `f16` disables Core ML and overrides the model path to F16. The default ordinary lab launch remains `coreml-q8`.

Use `summarize_files.py <work> <output.json>` after all three silent runs. It requires eight successful cycles per variant, identical decoded PCM hashes, file-input telemetry, no microphone capture and no playback. Review private source/translation results separately: exact agreement is not an accuracy score.

If idle memory pressure unloads recognition, the UI test can tap the existing Prepare button before the next file. Each intervention is logged as `VOICE_LAB_MANUAL_PREPARE` and counted in the summary; it must not be presented as uninterrupted residency. Retain failed/interrupted runs separately and report thermal differences before comparing speed.
