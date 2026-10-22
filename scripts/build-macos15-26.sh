#!/bin/bash
# Build the compatibility download separately from an untracked project copy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KAT_MAC_PROFILE=macos15
python3 "$ROOT/scripts/prepare-macos15-runtime.py"
# Generate into an untracked directory: the tracked apps/macos project stays the modern profile.
PROJECT_DIR="$ROOT/.build/macos15-project"
KAT_MAC_PROJECT_DIR="$PROJECT_DIR" python3 "$ROOT/scripts/generate-macos-project.py"
xcodebuild -project "$PROJECT_DIR/KatTranslatorMac.xcodeproj" \
  -scheme KatTranslatorMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$ROOT/.build/MacOS15DerivedData" build
KAT_MAC_APP="$ROOT/.build/MacOS15DerivedData/Build/Products/Release/Kat translator.app" \
  bash "$ROOT/scripts/package-macos.sh"
