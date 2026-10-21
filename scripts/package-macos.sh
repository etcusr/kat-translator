#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/update-animation-gallery.py" --check
APP="${KAT_MAC_APP:-$ROOT/.build/MacDerivedData/Build/Products/Release/Kat translator.app}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
PROFILE="${KAT_MAC_PROFILE:-modern}"
case "$PROFILE" in
  modern) SUFFIX="" ;;
  macos15) SUFFIX="-macos15-26" ;;
  *) echo "Unknown Mac profile: $PROFILE" >&2; exit 1 ;;
esac
NAME="Kat-translator-${VERSION}-build${BUILD}-mac-arm64${SUFFIX}"
OUT="$ROOT/dist/macos"
STAGE="$ROOT/.build/macos/dmg-stage${SUFFIX}"
# A stable certificate gives macOS a designated requirement shared by updates.
# Ad-hoc signatures instead bind privacy grants to one executable's cdhash.
# Keep explicit overrides (including '-' for disposable ad-hoc builds), but do
# not silently fall back to ad-hoc when the signing key is inaccessible.
SIGNING_IDENTITY=$(python3 "$ROOT/scripts/mac-signing.py")
mkdir -p "$OUT" "$STAGE"
# Replace only the previously staged build, never models or source files.
rsync -a --delete "$APP/" "$STAGE/Kat translator.app/"
# Hosted XCTest bundles are development-only and must not ship.
if [ -d "$STAGE/Kat translator.app/Contents/PlugIns" ]; then
  find "$STAGE/Kat translator.app/Contents/PlugIns" -maxdepth 1 -type d \( -name '*.xctest' -o -name '*.xctest.dSYM' \) -exec /bin/rm -rf '{}' +
fi
codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/apps/macos/KatMac.entitlements" "$STAGE/Kat translator.app"
codesign --verify --deep --strict "$STAGE/Kat translator.app"
python3 "$ROOT/scripts/validation/check-macos-bundle.py" "$STAGE/Kat translator.app" > "$ROOT/.build/macos/dependency-audit${SUFFIX}.json"
ln -sfn /Applications "$STAGE/Applications"
if [ "$PROFILE" = "macos15" ]; then
  cp "$ROOT/docs/macos/INSTALL-macos15.txt" "$STAGE/INSTALL.txt"
else
  cp "$ROOT/docs/macos/INSTALL.txt" "$STAGE/INSTALL.txt"
fi
hdiutil create -volname 'Kat translator' -srcfolder "$STAGE" -ov -format UDZO "$OUT/$NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Kat translator.app" "$OUT/$NAME.zip"
(cd "$OUT" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > "$NAME-SHA256SUMS.txt")
