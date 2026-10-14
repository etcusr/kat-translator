#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Dependencies/vendor/whisper.cpp"
REVISION=927cfce34f31707e17f2bff35c349632fb9e2c3a
if [ ! -d "$SOURCE/.git" ]; then
  git clone --depth 1 --branch v1.9.4 https://github.com/ggml-org/whisper.cpp.git "$SOURCE"
fi
[ "$(git -C "$SOURCE" rev-parse HEAD)" = "$REVISION" ] || { echo 'Unexpected whisper revision'; exit 1; }
OUT="$ROOT/Dependencies/build"
mkdir -p "$OUT/headers"
cp "$SOURCE/include/whisper.h" "$SOURCE/ggml/include/ggml"*.h "$OUT/headers/"
for SDK in iphoneos iphonesimulator; do
  BUILD="$OUT/$SDK"
  cmake -S "$SOURCE" -B "$BUILD" -G 'Unix Makefiles' \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_SERVER=OFF -DWHISPER_COREML=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BLAS=ON \
    -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  cmake --build "$BUILD" --config Release -j 6
  LIBS=()
  while IFS= read -r lib; do LIBS+=("$lib"); done < <(find "$BUILD/src" "$BUILD/ggml/src" -name '*.a' -type f | sort)
  xcrun libtool -static -o "$OUT/libwhisper-$SDK.a" "${LIBS[@]}"
done
if [ -d "$OUT/whisper.xcframework" ]; then rm -rf "$OUT/whisper.xcframework"; fi
xcodebuild -create-xcframework \
  -library "$OUT/libwhisper-iphoneos.a" -headers "$OUT/headers" \
  -library "$OUT/libwhisper-iphonesimulator.a" -headers "$OUT/headers" \
  -output "$OUT/whisper.xcframework"
