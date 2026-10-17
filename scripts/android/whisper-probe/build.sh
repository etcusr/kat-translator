#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../env.sh"
variant="${1:-arm82}"
case "$variant" in
  baseline) runtime="$KAT_ROOT/.build/android-media/whisper" ;;
  arm82) runtime="$KAT_ROOT/.build/android-media/whisper-arm82" ;;
  i8mm) runtime="$KAT_ROOT/.build/android-media/whisper-i8mm" ;;
  *) echo "Usage: $0 [baseline|arm82|i8mm]" >&2; exit 2 ;;
esac
probe_out="$KAT_ROOT/.build/whisper-native-probe"
mkdir -p "$probe_out"
"$ANDROID_HOME/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android31-clang++" \
 -O2 -std=c++17 -static-libstdc++ \
 -I "$KAT_ROOT/Dependencies/vendor/whisper.cpp/include" \
 -I "$KAT_ROOT/Dependencies/vendor/whisper.cpp/ggml/include" \
 -I "$KAT_ROOT/.build/android-media/include" "$KAT_ROOT/scripts/android/whisper-probe/main.cpp" \
 -Wl,--start-group "$runtime/whisper/src/libwhisper.a" \
 "$runtime/whisper/ggml/src/libggml.a" "$runtime/whisper/ggml/src/libggml-cpu.a" \
 "$runtime/whisper/ggml/src/libggml-base.a" -Wl,--end-group \
 -L "$KAT_ROOT/.build/android-media/jniLibs/arm64-v8a" -lsherpa-onnx-c-api -lonnxruntime \
 -llog -landroid -lm -latomic -Wl,-rpath,'$ORIGIN' -o "$probe_out/whisper-$variant"
