# Multilingual Whisper tiny/base comparison

These are research candidates, not catalog entries or a new default. Model URLs,
pinned revision, SHA-256 and byte counts are recorded in
`whisper-small-candidates.json`. The original upstream download script points to
[the ggerganov model repository](https://huggingface.co/ggerganov/whisper.cpp).
Both files were downloaded and independently SHA-256 verified on 2026-10-12.
They remain in the single shared cache `model-store/research/whisper-asr/`.

Use `org.openoffline.translator.android.WhisperCandidateTest`. The test APK needs
the new test source and RU fixture, but no production or native source changes.
The root/device owner runs each command individually:

1. Push `ggml-tiny.bin` and `ggml-base.bin` from the shared cache to
   `/data/local/tmp/kat-asr-research/` using ADB. This is shell staging only.
2. Select `#importCandidate` with instrumentation arguments `candidate=tiny`
   and then `candidate=base`. Optional `fixtureRoot` defaults to the staging
   directory above. The test reads the source through UiAutomation's shell pipe,
   verifies pinned size/SHA, and writes/renames the model inside app-owned
   `noBackupFilesDir/asr-research`. It never writes the model catalog, preferences,
   history, or the existing installed model.
3. Run `#tinyEnglish`, then `#tinyRussian`. If worthwhile, run
   `#baseEnglish` and `#baseRussian`. Each method has a 30-second native cancellation
   budget (`candidateTimeoutSeconds`, range 1–60), with a 120-second outer test
   timeout. The budget is a limit, not a predicted runtime.
4. Inspect each `ASR_CANDIDATE` JSON line for actual text, word error rate,
   critical-word omissions, elapsed seconds and real-time factor. Failed word
   assertions still print the measured transcript. A model must preserve the
   English negation and critical order/train words, and the Russian voice/train/
   departure/five words. This two-fixture screen is not a broad accuracy claim.

The English fixture is the existing synthetic Piper recording used by the
large-v3-turbo baseline (4.447 s, source 22,050 Hz). The Russian fixture is the
shared Supertonic preview from `scripts/validation/multilingual-voice-previews.c`,
resampled to PCM16/16 kHz (6.520 s). JSON sidecars pin the exact audio and expected
texts. Tests verify those hashes and use the existing `AudioImport` decoder.
Only `OfflineMedia.transcribe` is timed, including each model's fresh load.

No Activity is launched: compare these measurements with the existing standalone
`MediaPipelineTest#asr` baseline. Foreground UI scheduling previously changed CPU
behavior materially, so actual UI latency and cancellation must be validated
separately before choosing a production default. No benchmark has been run on the
Pixel as part of preparing these files.
