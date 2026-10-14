#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT2="$ROOT/Dependencies/vendor/CTranslate2"
SPM="$ROOT/Dependencies/vendor/sentencepiece"
mkdir -p "$ROOT/Dependencies/vendor" "$ROOT/Dependencies/build/opus"
if [ ! -d "$CT2" ]; then git clone --depth 1 --branch v4.6.0 https://github.com/OpenNMT/CTranslate2.git "$CT2"; fi
if [ ! -d "$SPM" ]; then git clone --depth 1 --branch v0.2.1 https://github.com/google/sentencepiece.git "$SPM"; fi
[ "$(git -C "$CT2" rev-parse HEAD)" = 617405f4b050e994e829d527da6caa0e0030afe7 ]
[ "$(git -C "$SPM" rev-parse HEAD)" = 31646a467d2051eb904e0b45de3a73e91fe1c1e3 ]
git -C "$CT2" submodule update --init --recursive --depth 1 third_party/spdlog third_party/ruy
if git -C "$CT2" apply --check "$ROOT/shared/native/OpusRuntime/mobile-cancel.patch" 2>/dev/null; then
 git -C "$CT2" apply "$ROOT/shared/native/OpusRuntime/mobile-cancel.patch"
else
 git -C "$CT2" apply --reverse --check "$ROOT/shared/native/OpusRuntime/mobile-cancel.patch"
fi
for SDK in iphoneos iphonesimulator macosx; do
 case "$SDK" in
  iphoneos) FLAVOR=ios; FLAGS=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0);;
  iphonesimulator) FLAVOR=simulator; FLAGS=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0);;
  macosx) FLAVOR=macos; FLAGS=(-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0);;
 esac
 BUILD="$ROOT/.build/opus/$FLAVOR"
 cmake -S "$ROOT/shared/native/OpusRuntime" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)" -DCMAKE_OSX_ARCHITECTURES=arm64 "${FLAGS[@]}"
 cmake --build "$BUILD" --target OpusRuntime -j4
 FRAMEWORK="$BUILD/OpusRuntime.framework"
 if [ "$SDK" = macosx ]; then CONTENTS="$FRAMEWORK/Versions/A"; else CONTENTS="$FRAMEWORK"; fi
 mkdir -p "$CONTENTS/Headers" "$CONTENTS/Modules"
 cp "$ROOT/shared/native/OpusRuntime/OpusRuntime.h" "$CONTENTS/Headers/OpusRuntime.h"
 printf 'framework module OpusRuntime { umbrella header "OpusRuntime.h" export * }\n' > "$CONTENTS/Modules/module.modulemap"
 if [ "$SDK" = macosx ]; then
  [ -e "$FRAMEWORK/Headers" ] || ln -s Versions/Current/Headers "$FRAMEWORK/Headers"
  [ -e "$FRAMEWORK/Modules" ] || ln -s Versions/Current/Modules "$FRAMEWORK/Modules"
 fi
 install_name_tool -id @rpath/OpusRuntime.framework/OpusRuntime "$FRAMEWORK/OpusRuntime"
done
DEST="$ROOT/Dependencies/build/opus/OpusRuntime.xcframework"
# Only replace this script's generated framework, never other translation runtimes.
if [ -d "$DEST" ]; then mv "$DEST" "$DEST.previous-$(date +%s)"; fi
xcodebuild -create-xcframework -framework "$ROOT/.build/opus/ios/OpusRuntime.framework" -framework "$ROOT/.build/opus/simulator/OpusRuntime.framework" -framework "$ROOT/.build/opus/macos/OpusRuntime.framework" -output "$DEST"
