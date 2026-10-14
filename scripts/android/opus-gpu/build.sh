#!/bin/bash
# Research-only standalone programs. Never changes the installed APK or product backend.
set -euo pipefail
source "$(dirname "$0")/../env.sh"
cd "$KAT_ROOT"
KAT_PROBE_SOURCE="$KAT_ROOT/.build/opus-vulkan-lab/vendor/sussurro"
KAT_PROBE_COMMIT=298a657fc8710db844e0b82925b9e454b456fa81
if [ ! -d "$KAT_PROBE_SOURCE/.git" ]; then
    git clone https://github.com/whispem/sussurro.cpp.git "$KAT_PROBE_SOURCE"
    git -C "$KAT_PROBE_SOURCE" checkout --detach "$KAT_PROBE_COMMIT"
fi
[ "$(git -C "$KAT_PROBE_SOURCE" rev-parse HEAD)" = "$KAT_PROBE_COMMIT" ]
[ "$(git -C Dependencies/vendor/llama.cpp rev-parse HEAD)" = d81235049384534c167caea52b85a694f6103d14 ]
# Build/reuse the same pinned Android Vulkan libraries as the Index diagnostics.
[ -f .build/mali-kernels/native/llama/ggml/src/ggml-vulkan/libggml-vulkan.a ] || bash scripts/android/build-gpu-probes.sh
python3 scripts/android/opus-gpu/prepare-probe.py
cmake -S scripts/android/opus-gpu -B .build/opus-vulkan-lab/build -G Ninja \
 -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/28.2.13676358/build/cmake/android.toolchain.cmake" \
 -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31 -DANDROID_STL=c++_static -DCMAKE_BUILD_TYPE=Release
cmake --build .build/opus-vulkan-lab/build --target opus-gpu-probe opus-cpu-control -j5
