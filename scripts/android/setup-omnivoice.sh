#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KAT_ROOT"
# Same prepared upstream commit + cancellation patch as Apple's build.
# scripts/build-omnivoice.sh owns vendor preparation; never alter it here.
test "$(git -C Dependencies/vendor/omnivoice-mobile rev-parse HEAD)" = "53e6c2066150802ad3cd4b655b31c696e78e0019"
test "$(git -C Dependencies/vendor/omnivoice-mobile/ggml rev-parse HEAD)" = "40e16e4a814f7fe851a0c486fb9e8c722e957830"
git -C Dependencies/vendor/omnivoice-mobile apply --reverse --check "$KAT_ROOT/shared/native/OmniVoice/mobile-cancel.patch"
cmake -S apps/android/inference/src/main/cpp/omnivoice -B .build/android-media/omnivoice -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_HOME/ndk/28.2.13676358/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31 -DANDROID_STL=c++_shared -DCMAKE_BUILD_TYPE=Release
cmake --build .build/android-media/omnivoice --target kat_omnivoice -j 6
