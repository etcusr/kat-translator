[Русский](README.ru.md)

# Isolated WhisperKit iPhone stream comparison

This lab uses a separate `app.kattranslator.whisper-research` container. It never installs over Kat, reads its private container, or changes its preferences. Model and private audio copies belong only in ignored `.build` directories. Provisioning needs a developer signing team and an unlocked connected iPhone.

## Method

- Pin Argmax `argmax-oss-swift` to `9f99b5cb6a907730543823ad271b82532782a899` in a disposable checkout.
- Stage the recommended `openai_whisper-large-v3-v20240930_626MB` Core ML model and the matching Whisper large-v3-turbo tokenizer locally. Validate remote LFS hashes before copying.
- `prepare.py` creates a standalone Xcode project, copies the current Kat Index backend into it, and links the existing iOS TranslationRuntime and OfflineCore. It adds only lab accessors, a file-input permission bypass, and pass timing to the disposable Argmax stream actor. Upstream segmentation, confirmation and VAD are unchanged.
- `ReplayAudio` delivers the supplied 16 kHz mono Float32 PCM in 100 ms frames with real-time deadlines, using upstream relative-energy calculations. No microphone, speaker or TTS is involved.
- Stock `AudioStreamTranscriber` holds two segments provisionally. Only complete sentences in its confirmed prefix are queued to the existing Index 9B MTP2 backend. ASR can continue while the serial translation queue runs.
- After the last input frame, finish the in-flight pass and decode only the unpublished interval using `clipTimestamps`. No full-recording verification, replacement of published text, or retranslation of the prefix is performed.
- Preparation/Core ML loading is outside replay timing. Start only after 30 consecutive seconds at nominal thermal state (up to seven minutes). Abort replay at serious/critical heat. Record thermal maximum, footprint, individual recognition passes, confirmed events and translation completion times.
- This compares complete streaming configurations, **not just engines**: Core ML conversion/quantization, VAD, confirmation and scheduling differ from Kat's current Whisper.cpp Q8 + LocalAgreement implementation. First draft, first confirmed ASR, and first completed translation are separate metrics.

## Run

Pass local paths and signing/device values explicitly; never commit them:

```
swift ExportPCM.swift <baseline-16k-mono-aiff> <private-16k-f32>
python3 prepare.py --work <ignored-work-dir> --argmax <disposable-pinned-checkout> --team <team>
xcodebuild build -project <work>/WhisperKitLab.xcodeproj -scheme WhisperKitLab -configuration Release -destination 'generic/platform=iOS' -derivedDataPath <work>/Derived -allowProvisioningUpdates
python3 provision.py --work <work> --device <device> --index <existing-Index-GGUF> --pcm <private-16k-f32>
```

Launch only the research bundle with `LAB_RUN=run-a`, `GGML_METAL_NO_RESIDENCY=1`. An ordinary launch does nothing. Fetch `Documents/status.txt` and `Documents/run-a.json` from this research container. Repeat only after cooling and if the first run justifies it. Preserve private outputs locally; publish aggregate metrics and qualitative findings rather than personal recordings/transcripts/device identifiers.

Compare against clearly dated baseline runs using the exact same PCM hash. Do not call file replay a live microphone or production UI acceptance test. Read-only before/after inventories and preference comparison can verify that the main app remained unchanged. The lab's copied model/audio files may be removed with the lab container after results have been preserved; never remove the main app.

[Experiment report](../../../docs/publication/whisperkit-stream-2026-10-22.md)
