#!/bin/bash
# Build the compatibility download separately; restore the default project on exit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KAT_MAC_PROFILE=macos15
python3 "$ROOT/scripts/prepare-macos15-runtime.py"
trap 'KAT_MAC_PROFILE=modern python3 "$ROOT/scripts/generate-macos-project.py"' EXIT
python3 "$ROOT/scripts/generate-macos-project.py"
xcodebuild -project "$ROOT/apps/macos/KatTranslatorMac.xcodeproj" \
  -scheme KatTranslatorMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$ROOT/.build/MacOS15DerivedData" build
KAT_MAC_APP="$ROOT/.build/MacOS15DerivedData/Build/Products/Release/Kat translator.app" \
  bash "$ROOT/scripts/package-macos.sh"
