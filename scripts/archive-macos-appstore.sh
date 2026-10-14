#!/bin/bash
# Mac App Store build: sandboxed, store Bundle ID, separate DerivedData.
# The regular direct build (package-macos.sh) and its project settings stay unchanged.
# Usage: KAT_MAC_STORE_BUILD=61 [KAT_MAC_STORE_VERSION=1.0] scripts/archive-macos-appstore.sh [export|upload]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-export}"
case "$DESTINATION" in export|upload) ;; *) echo "Destination must be export or upload" >&2; exit 1 ;; esac
VERSION="${KAT_MAC_STORE_VERSION:-1.0}"
BUILD="${KAT_MAC_STORE_BUILD:?Set KAT_MAC_STORE_BUILD to a build number not yet uploaded}"
BUNDLE_ID="${KAT_MAC_STORE_BUNDLE_ID:-app.kattranslator}"
TEAM="${KAT_APPLE_TEAM_ID:-$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$ROOT/apps/ios/Config/Signing.local.xcconfig" 2>/dev/null)}"
[ -n "$TEAM" ] || { echo "Set KAT_APPLE_TEAM_ID or apps/ios/Config/Signing.local.xcconfig" >&2; exit 1; }
OUT="$ROOT/.build/macos-appstore/$VERSION-$BUILD"
ARCHIVE="$OUT/Kat-translator-mas.xcarchive"
mkdir -p "$OUT"

# Store Info.plist: same content, store version/build.
python3 - "$ROOT/apps/macos/Info.plist" "$OUT/Info.plist" "$VERSION" "$BUILD" <<'EOF'
import plistlib, sys
data = plistlib.loads(open(sys.argv[1], 'rb').read())
data['CFBundleShortVersionString'] = sys.argv[3]
data['CFBundleVersion'] = sys.argv[4]
data['KatBuildProfile'] = 'mac-app-store'
# Store build carries no TLS/crypto library; HTTPS is the OS stack (as iOS).
data['ITSAppUsesNonExemptEncryption'] = False
open(sys.argv[2], 'wb').write(plistlib.dumps(data, sort_keys=False))
EOF

xcodebuild -project "$ROOT/apps/macos/KatTranslatorMac.xcodeproj" -scheme KatTranslatorMac \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$ROOT/.build/MacStoreDerivedData" -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  archive \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGN_ENTITLEMENTS="$ROOT/apps/macos/KatMacStore.entitlements" \
  ENABLE_APP_SANDBOX=YES INFOPLIST_FILE="$OUT/Info.plist" ENABLE_TESTABILITY=NO \
  2>&1 | tee "$OUT/archive.log" | grep -E "error:|warning: .*sign|ARCHIVE (SUCCEEDED|FAILED)" || true
[ -d "$ARCHIVE/Products/Applications/Kat translator.app" ] || { echo "Archive failed, see $OUT/archive.log" >&2; exit 1; }

APP="$ARCHIVE/Products/Applications/Kat translator.app"
# Development-only test bundles must never reach the store package.
if find "$APP" -name '*.xctest' | grep -q .; then echo "xctest bundle in archive" >&2; exit 1; fi
codesign --verify --deep --strict "$APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q app-sandbox || { echo "App is not sandboxed" >&2; exit 1; }
SHM="$APP/Contents/Resources/OpusPython/torch/bin/torch_shm_manager"
for helper in "$APP/Contents/MacOS/OpusPython" "$SHM"; do
  codesign -d --entitlements - --xml "$helper" 2>/dev/null | grep -q security.inherit || { echo "Helper lacks inherited sandbox: $helper" >&2; exit 1; }
done
# Apple rejects any executable without the sandbox entitlement; only the app and sandboxed helpers may remain.
EXTRA=$(find "$APP" -type f -exec file {} + | grep 'Mach-O 64-bit executable' | cut -d: -f1 | grep -v -e '/Contents/MacOS/Kat translator$' -e '/Contents/MacOS/OpusPython$' -e '/torch/bin/torch_shm_manager$' || true)
[ -z "$EXTRA" ] || { echo "Unexpected executables: $EXTRA" >&2; exit 1; }
# Nested signatures outside standard locations keep the development certificate (ITMS-90284).
SIGNED_RESOURCES=$(find "$APP/Contents/Resources" -path '*/_CodeSignature' -prune -print | grep -v '/Contents/Resources/OpusPython/' || true)
[ -z "$SIGNED_RESOURCES" ] || { echo "Signed bundles in Resources: $SIGNED_RESOURCES" >&2; exit 1; }
# Store build ships no TLS/crypto implementation (export compliance, as on iOS).
CRYPTO=$(find "$APP" -type f \( -name '*.so' -o -name '*.dylib' -o -perm +111 \) -print0 | xargs -0 grep -l -a -E 'OpenSSL 3\.|_SSL_new|OPENSSL_init_crypto|rustls|BoringSSL' 2>/dev/null || true)
[ -z "$CRYPTO" ] || { echo "Crypto library in store build: $CRYPTO" >&2; exit 1; }

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>destination</key><string>$DESTINATION</string>
<key>method</key><string>app-store-connect</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>uploadSymbols</key><true/>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export-$DESTINATION" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates 2>&1 | tee "$OUT/export-$DESTINATION.log" | tail -5
grep -q "EXPORT SUCCEEDED\|Upload succeeded\|UPLOAD SUCCEEDED" "$OUT/export-$DESTINATION.log" || { echo "Export failed, see $OUT/export-$DESTINATION.log" >&2; exit 1; }
echo "$OUT"
