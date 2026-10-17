# Android media library link repair — 17 October 2026

A fresh Android build failed with `undefined symbol: ot_prepare_inference_privacy`. The shared `SpeechRuntime.c` already calls this helper before creating a voice, but the Android `kat_media` target omitted its implementation. `media.cmake` now includes the existing `shared/native/app/Privacy/InferencePrivacy.c`.

Validation: the failure was reproduced, then `:app:assembleDebug :app:assembleDebugAndroidTest` completed successfully. The existing telemetry environment initialization is retained. No speech model, thread count, synthesis algorithm or shared Apple code changed. This build check alone does not establish runtime speed or privacy coverage.
