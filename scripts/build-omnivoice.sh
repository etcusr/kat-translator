#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Dependencies/vendor/omnivoice-mobile"
REVISION=53e6c2066150802ad3cd4b655b31c696e78e0019
if [ ! -d "$SOURCE" ]; then
 git clone https://github.com/ServeurpersoCom/omnivoice.cpp.git "$SOURCE"
 git -C "$SOURCE" checkout "$REVISION"
 git -C "$SOURCE" submodule update --init --recursive
fi
[ "$(git -C "$SOURCE" rev-parse HEAD)" = "$REVISION" ]
[ "$(git -C "$SOURCE/ggml" rev-parse HEAD)" = 40e16e4a814f7fe851a0c486fb9e8c722e957830 ]
if git -C "$SOURCE" apply --check "$ROOT/shared/native/OmniVoice/mobile-cancel.patch" 2>/dev/null; then
 git -C "$SOURCE" apply "$ROOT/shared/native/OmniVoice/mobile-cancel.patch"
else
 git -C "$SOURCE" apply --reverse --check "$ROOT/shared/native/OmniVoice/mobile-cancel.patch"
fi
OUT="$ROOT/Dependencies/build/omnivoice"
mkdir -p "$OUT"
for SDK in iphoneos iphonesimulator macosx; do
 case "$SDK" in
  iphoneos) FLAVOR=ios; FLAGS=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0);;
  iphonesimulator) FLAVOR=simulator; FLAGS=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0);;
  macosx) FLAVOR=macos; FLAGS=(-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0);;
 esac
 BUILD="$ROOT/.build/omnivoice/$FLAVOR"
 cmake -S "$ROOT/shared/native/OmniVoice" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)" -DCMAKE_OSX_ARCHITECTURES=arm64 "${FLAGS[@]}"
 cmake --build "$BUILD" --target OmniVoiceRuntime -j4
 FRAMEWORK="$BUILD/OmniVoiceRuntime.framework"
 if [ "$SDK" = macosx ]; then CONTENTS="$FRAMEWORK/Versions/A"; else CONTENTS="$FRAMEWORK"; fi
 mkdir -p "$CONTENTS/Headers" "$CONTENTS/Modules"
 cp "$SOURCE/src/omnivoice.h" "$CONTENTS/Headers/omnivoice.h"
 printf 'framework module OmniVoiceRuntime { umbrella header "omnivoice.h" export * }\n' > "$CONTENTS/Modules/module.modulemap"
 if [ "$SDK" = macosx ]; then
  [ -e "$FRAMEWORK/Headers" ] || ln -s Versions/Current/Headers "$FRAMEWORK/Headers"
  [ -e "$FRAMEWORK/Modules" ] || ln -s Versions/Current/Modules "$FRAMEWORK/Modules"
 fi
 # CMake emits a framework without an rpath install name when built outside Xcode.
 install_name_tool -id @rpath/OmniVoiceRuntime.framework/OmniVoiceRuntime "$FRAMEWORK/OmniVoiceRuntime"
done
DEST="$OUT/OmniVoiceRuntime.xcframework"
if [ -d "$DEST" ]; then rm -rf "$DEST"; fi
xcodebuild -create-xcframework -framework "$ROOT/.build/omnivoice/ios/OmniVoiceRuntime.framework" -framework "$ROOT/.build/omnivoice/simulator/OmniVoiceRuntime.framework" -framework "$ROOT/.build/omnivoice/macos/OmniVoiceRuntime.framework" -output "$DEST"
