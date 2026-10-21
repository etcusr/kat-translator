# Isolated streaming ASR probe

**English** | [Русский](README.ru.md)

`probe.c` feeds explicitly supplied private 16 kHz mono Float32 PCM to a stateful sherpa-onnx recognizer. It never reads application containers, invokes a microphone, translates, or changes models/settings. Output JSONL contains private transcripts; keep it outside Git.

Use `alphacep/vosk-model-streaming-ru` revision `83bbf6f40059480e96251be8aed3d32bc7c80c33`, with `am-onnx/{encoder,decoder,joiner}.int8.onnx` and `lang/tokens.txt`. Verify weight hashes against the model repository before use. The model is Apache-2.0. The experiment reuses the repository's installed sherpa-onnx library; it does not download dependencies automatically.

From the repository root on Apple Silicon:

```sh
mkdir -p .build/streaming-asr-lab
clang -O2 scripts/research/streaming-asr/probe.c \
  -I Dependencies/build/speech-macos/sherpa-onnx.xcframework/macos-arm64_x86_64/Headers \
  -L Dependencies/build/speech-macos/sherpa-onnx.xcframework/macos-arm64_x86_64 \
  -lsherpa-onnx-c-api \
  -Wl,-rpath,"$PWD/Dependencies/build/speech-macos/sherpa-onnx.xcframework/macos-arm64_x86_64" \
  -o .build/streaming-asr-lab/probe
.build/streaming-asr-lab/probe MODEL_DIRECTORY INPUT.f32 OUTPUT.jsonl 0 1
```

Last arguments: real-time pacing (`0` accelerated file input, `1` wait for each 160 ms chunk) and beam decoding (`1` modified beam/10 paths, `0` greedy). One stream is retained throughout; no arbitrary endpoint reset. A final 600 ms silence flushes pending decoder output; it is not re-recognition. Partial text is tentative, not a completed translation phrase. CPU compute excludes load, pacing and result serialization. This probe has only been run on Mac; the optional C entry point is not an iPhone validation.

[Results and limitations](../../../docs/publication/voice-streaming-quality-2026-10-22.md).
