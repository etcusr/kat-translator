#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../env.sh"
probe_out="$KAT_ROOT/.build/asr-native-probe"
mkdir -p "$probe_out"
"$ANDROID_HOME/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android31-clang++" \
 -O2 -std=c++17 -static-libstdc++ -I "$KAT_ROOT/.build/android-media/include" \
 "$KAT_ROOT/scripts/android/asr-probe/main.cpp" -L "$KAT_ROOT/.build/android-media/jniLibs/arm64-v8a" \
 -lsherpa-onnx-c-api -lonnxruntime -Wl,-rpath,'$ORIGIN' -o "$probe_out/asr-probe"
