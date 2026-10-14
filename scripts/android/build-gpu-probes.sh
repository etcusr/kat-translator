#!/bin/bash
# Separate build tree; diagnostics are never packaged into the application.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KAT_ROOT"
cmake -S apps/android/inference/src/main/cpp -B .build/mali-kernels/native -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/28.2.13676358/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31 -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DKAT_GPU_DIAGNOSTICS=ON
cmake --build .build/mali-kernels/native --target kat_gpu_probe llama-server -j5
