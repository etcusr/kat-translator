#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Dependencies/vendor/llama.cpp"
REVISION=d81235049384534c167caea52b85a694f6103d14
if [ ! -d "$SOURCE/.git" ]; then git clone --depth 1 --branch v0.6.0 https://github.com/ggml-org/llama.cpp.git "$SOURCE"; fi
[ "$(git -C "$SOURCE" rev-parse HEAD)" = "$REVISION" ]
OUT="$ROOT/Dependencies/build/translation"
# Optional SDK list permits an iOS-only rebuild without replacing the desktop runtime.
SDKS=("$@"); if [ "${#SDKS[@]}" -eq 0 ]; then SDKS=(iphoneos iphonesimulator macosx); fi
for SDK in "${SDKS[@]}"; do
  case "$SDK" in iphoneos|iphonesimulator|macosx) ;; *) echo "Unsupported SDK: $SDK" >&2; exit 1;; esac
  COMMON=OFF; MTP_FLAGS=(); MTP_SOURCES=()
  if [ "$SDK" != macosx ]; then
    COMMON=ON
    MTP_FLAGS=(-DKAT_IOS_MTP=1 -I"$SOURCE/common" -I"$SOURCE/vendor")
    MTP_SOURCES=("$ROOT/shared/native/TranslationRuntime/IndexMTP.cpp")
  fi
  BUILD="$OUT/$SDK"; FLAGS=(); TARGET=arm64-apple-ios18.0
  if [ "$SDK" = iphonesimulator ]; then TARGET=arm64-apple-ios18.0-simulator; fi
  if [ "$SDK" = macosx ]; then TARGET=arm64-apple-macos14.0; FLAGS=(-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0); else FLAGS=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0); fi
  SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
  cmake -S "$SOURCE" -B "$BUILD" -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release \
    "${FLAGS[@]}" -DCMAKE_OSX_SYSROOT="$SYSROOT" -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF \
    -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_COMMON="$COMMON" -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_MTMD=OFF -DLLAMA_CURL=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BLAS=ON -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  cmake --build "$BUILD" --config Release -j 6
  FRAMEWORK="$BUILD/TranslationRuntime.framework"; mkdir -p "$FRAMEWORK/Headers" "$FRAMEWORK/Modules"
  cp "$ROOT/shared/native/TranslationRuntime/TranslationRuntime.h" "$FRAMEWORK/Headers/"
  LIBS=(); while IFS= read -r lib; do LIBS+=("$lib"); done < <(find "$BUILD/src" "$BUILD/ggml/src" -type f -name '*.a' | sort)
  if [ "$COMMON" = ON ]; then
    LIBS+=("$BUILD/common/libllama-common.a" "$BUILD/common/libllama-common-base.a" "$BUILD/vendor/cpp-httplib/libcpp-httplib.a")
  fi
  # Some pinned builds place hashing support in a separate archive.
  if [ -f "$BUILD/vendor/hash/libvendor-hash.a" ]; then LIBS+=("$BUILD/vendor/hash/libvendor-hash.a"); fi
  xcrun --sdk "$SDK" clang++ -target "$TARGET" -isysroot "$SYSROOT" -std=c++17 -O2 -dynamiclib \
    "$ROOT/shared/native/TranslationRuntime/TranslationRuntime.cpp" "${MTP_SOURCES[@]}" "${MTP_FLAGS[@]}" -I"$SOURCE/include" -I"$SOURCE/ggml/include" \
    -Wl,-all_load "${LIBS[@]}" -framework Foundation -framework Metal -framework MetalKit -framework Accelerate \
    -Wl,-exported_symbols_list,"$ROOT/shared/native/TranslationRuntime/exports.txt" \
    -install_name @rpath/TranslationRuntime.framework/TranslationRuntime -o "$FRAMEWORK/TranslationRuntime"
  cat > "$FRAMEWORK/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.openoffline.TranslationRuntime</string><key>CFBundleExecutable</key><string>TranslationRuntime</string><key>CFBundleName</key><string>TranslationRuntime</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string><key>MinimumOSVersion</key><string>18.0</string></dict></plist>
PLIST
  echo 'framework module TranslationRuntime { umbrella header "TranslationRuntime.h" export * }' > "$FRAMEWORK/Modules/module.modulemap"
done
if [ -d "$OUT/TranslationRuntime.xcframework" ]; then rm -rf "$OUT/TranslationRuntime.xcframework"; fi
xcodebuild -create-xcframework -framework "$OUT/iphoneos/TranslationRuntime.framework" -framework "$OUT/iphonesimulator/TranslationRuntime.framework" -output "$OUT/TranslationRuntime.xcframework"
