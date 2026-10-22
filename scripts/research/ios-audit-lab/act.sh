#!/bin/bash
# Run LAB_ACTIONS on the running Kat Audit Lab, then save a screenshot. It does not reliably install a rebuilt
# lab app: after a rebuild install it with `devicectl device install app` first. Usage: act.sh <work> <device> "<actions>" [screenshot.png]
set -uo pipefail
w=$(cd "$1" && pwd); device=$2; actions=$3; shot=${4:-$w/screen.png}
TEST_RUNNER_LAB_ACTIONS="$actions" xcodebuild test-without-building -project "$w/source/apps/ios/OfflineTranslator.xcodeproj" \
  -scheme OfflineTranslator -configuration Release -destination "id=$device" -derivedDataPath "$w/Derived" \
  -only-testing:TranslatorUITests/LabDriverUITests/testActions > "$w/act.log" 2>&1
status=$?
grep -E "LAB_STEP|LAB_MISSING|error:|passed \(|failed \(|skipped \(" "$w/act.log" | sed 's/^.*\(LAB_\)/\1/' | tail -20
awk '/LAB_DUMP_BEGIN/{f=1;next}/LAB_DUMP_END/{f=0}f' "$w/act.log" > "$w/dump.txt"
xcrun devicectl device capture screenshot --device "$device" --destination "$shot" >/dev/null 2>&1
echo "status=$status screenshot=$shot"
