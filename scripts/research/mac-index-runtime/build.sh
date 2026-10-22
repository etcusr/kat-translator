#!/bin/bash
# Research-only: macOS TranslationRuntime with the iPhone MTP path (KAT_IOS_MTP) plus an
# identical no-MTP control. Output stays in .build; Dependencies/build and the app are untouched.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SOURCE="$ROOT/Dependencies/vendor/llama.cpp"
[ "$(git -C "$SOURCE" rev-parse HEAD)" = d81235049384534c167caea52b85a694f6103d14 ]
OUT="$ROOT/.build/mac-index-runtime"; BUILD="$OUT/llama-macos-common"
mkdir -p "$OUT"
SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
cmake -S "$SOURCE" -B "$BUILD" -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_OSX_SYSROOT="$SYSROOT" -DCMAKE_OSX_ARCHITECTURES=arm64 -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_COMMON=ON \
  -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_MTMD=OFF -DLLAMA_CURL=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BLAS=ON -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF
cmake --build "$BUILD" --config Release -j "$(sysctl -n hw.ncpu)"
LIBS=(); while IFS= read -r lib; do LIBS+=("$lib"); done < <(find "$BUILD/src" "$BUILD/ggml/src" -type f -name '*.a' | sort)
LIBS+=("$BUILD/common/libllama-common.a" "$BUILD/common/libllama-common-base.a" "$BUILD/vendor/cpp-httplib/libcpp-httplib.a")
if [ -f "$BUILD/vendor/hash/libvendor-hash.a" ]; then LIBS+=("$BUILD/vendor/hash/libvendor-hash.a"); fi
link() { # $1 output, rest: extra sources/flags
  local out="$1"; shift
  xcrun clang++ -target arm64-apple-macos14.0 -isysroot "$SYSROOT" -std=c++17 -O2 -dynamiclib \
    "$ROOT/shared/native/TranslationRuntime/TranslationRuntime.cpp" "$@" -I"$SOURCE/include" -I"$SOURCE/ggml/include" \
    -Wl,-all_load "${LIBS[@]}" -framework Foundation -framework Metal -framework MetalKit -framework Accelerate \
    -Wl,-exported_symbols_list,"$ROOT/shared/native/TranslationRuntime/exports.txt" \
    -install_name @rpath/libTranslationRuntime.dylib -o "$out"
}
link "$OUT/libTranslationRuntime-mtp.dylib" "$ROOT/shared/native/TranslationRuntime/IndexMTP.cpp" -DKAT_IOS_MTP=1 -I"$SOURCE/common" -I"$SOURCE/vendor"
link "$OUT/libTranslationRuntime-nomtp.dylib"
xcrun clang++ -std=c++17 -dynamiclib -fobjc-arc "$ROOT/scripts/research/index-quantization/Memory.mm" \
  -framework Foundation -framework Metal -o "$OUT/libmetrics.dylib"
ls -la "$OUT"/*.dylib
