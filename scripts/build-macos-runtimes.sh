#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Dependencies/build/macos"
mkdir -p "$OUT"
for ENGINE in whisper llama; do
  SOURCE="$ROOT/Dependencies/vendor/$ENGINE.cpp"
  BUILD="$OUT/$ENGINE"
  cmake -S "$SOURCE" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BLAS=ON -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF -DWHISPER_COREML=OFF \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_MTMD=OFF -DLLAMA_CURL=OFF
  cmake --build "$BUILD" -j 6
  LIBS=(); while IFS= read -r lib; do LIBS+=("$lib"); done < <(find "$BUILD/src" "$BUILD/ggml/src" -name '*.a' -type f | sort)
  if [ "$ENGINE" = whisper ]; then
    xcrun libtool -static -o "$OUT/libwhisper.a" "${LIBS[@]}"
  else
    xcrun clang++ -target arm64-apple-macos15.0 -std=c++17 -O2 -dynamiclib \
      "$ROOT/shared/native/TranslationRuntime/TranslationRuntime.cpp" -I"$SOURCE/include" -I"$SOURCE/ggml/include" \
      -Wl,-all_load "${LIBS[@]}" -framework Foundation -framework Metal -framework MetalKit -framework Accelerate \
      -Wl,-exported_symbols_list,"$ROOT/shared/native/TranslationRuntime/exports.txt" \
      -install_name @rpath/libTranslationRuntime.dylib -o "$OUT/libTranslationRuntime.dylib"
  fi
done

# Reuse the pinned runtime/header inputs already prepared for the project.
PYTHON_ROOT=/opt/homebrew/opt/python@3.11/Frameworks/Python.framework/Versions/3.11
mkdir -p "$OUT/headers/onnxruntime" "$OUT/headers/sherpa-onnx"
rsync -a "$ROOT/Dependencies/build/speech/onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Headers/" "$OUT/headers/onnxruntime/"
rsync -a "$ROOT/Dependencies/build/speech-macos/sherpa-onnx.xcframework/macos-arm64_x86_64/Headers/sherpa-onnx/" "$OUT/headers/sherpa-onnx/"
cp "$ROOT/.build/wayu-env/lib/python3.11/site-packages/onnxruntime/capi/libonnxruntime.1.30.0.dylib" "$OUT/libonnxruntime.dylib"
cp "$PYTHON_ROOT/Python" "$OUT/libpython3.11.dylib"
install_name_tool -id @rpath/libonnxruntime.dylib "$OUT/libonnxruntime.dylib"
install_name_tool -id @rpath/libpython3.11.dylib "$OUT/libpython3.11.dylib"
