#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KAT_ROOT"
python3 scripts/android/setup-media.py
cmake -S apps/android/inference/src/main/cpp/whisper -B .build/android-media/whisper -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/28.2.13676358/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31 -DANDROID_STL=c++_shared -DCMAKE_BUILD_TYPE=Release -DKAT_WHISPER_ARM82=OFF
cmake --build .build/android-media/whisper --target kat_whisper -j 6
cmake -S apps/android/inference/src/main/cpp/whisper -B .build/android-media/whisper-arm82 -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/28.2.13676358/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31 -DANDROID_STL=c++_shared -DCMAKE_BUILD_TYPE=Release -DKAT_WHISPER_ARM82=ON
cmake --build .build/android-media/whisper-arm82 --target kat_whisper_arm82 -j 6
mkdir -p .build/android-media/whisper-optimized/arm64-v8a
cp .build/android-media/whisper-arm82/libkat_whisper_arm82.so .build/android-media/whisper-optimized/arm64-v8a/
