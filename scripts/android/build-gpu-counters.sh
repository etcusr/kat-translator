#!/bin/bash
# Official Arm counter library, isolated from production dependencies and APK.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KAT_ROOT"
SRC=.build/mali-research-tools/libGPUCounters
BUILD=.build/mali-research-tools/counters-build
REV=378c7b59e2dae87cbbffb0ac9cf96ed13c939823
if [ ! -d "$SRC" ]; then
  git init "$SRC"
  git -C "$SRC" fetch --depth 1 https://github.com/ARM-software/libGPUCounters.git "$REV"
  git -C "$SRC" checkout --detach FETCH_HEAD
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$REV" ]
NDK="$ANDROID_HOME/ndk/28.2.13676358"
cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31 -DANDROID_STL=c++_static -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --target hwcpipe -j5
"$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android31-clang++" \
  -std=c++14 -O2 -Wall -Wextra -Werror -static-libstdc++ \
  -I"$SRC/hwcpipe/include" -I"$SRC/backend/device/include" -I"$SRC/backend/device/src" \
  scripts/android/native/gpu_counters.cpp "$BUILD/hwcpipe/libhwcpipe.a" "$BUILD/backend/device/libdevice.a" \
  -latomic -lm -o "$BUILD/kat_gpu_counters"
