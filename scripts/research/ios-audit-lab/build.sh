#!/bin/bash
# Build and check Kat Audit Lab prepared by prepare.py. Usage: build.sh <work>
set -euo pipefail
w=$(cd "$1" && pwd)
app="$w/Derived/Build/Products/Release-iphoneos/OfflineTranslator.app"
xcodebuild -project "$w/source/apps/ios/OfflineTranslator.xcodeproj" -scheme OfflineTranslator -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$w/Derived" build > "$w/build.log" 2>&1 || { grep -E " error:" "$w/build.log" | head -20; exit 1; }
id=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$app/Info.plist")
name=$(/usr/libexec/PlistBuddy -c "Print CFBundleDisplayName" "$app/Info.plist")
[ "$id" = app.kattranslator.voicelab ] || { echo "unexpected bundle $id"; exit 1; }
[ ! -d "$app/PlugIns" ] || { echo "extension embedded"; exit 1; }
codesign --verify --deep --strict "$app"
codesign -d --entitlements - "$app" 2>/dev/null | grep -q increased-memory-limit || { echo "memory entitlement missing"; exit 1; }
echo "OK $name $id $(du -sh "$app" | cut -f1) commit $(cat "$w/commit.txt")"
