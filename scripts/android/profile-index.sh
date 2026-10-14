#!/bin/bash
# Uses an already built app/test APK. Never uploads or replaces model weights.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KAT_ROOT"
LABEL="${1:?Usage: profile-index.sh LABEL [instrumentation -e KEY VALUE ...]}"
shift
[[ "$LABEL" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid result label' >&2; exit 2; }
OUT="$KAT_ROOT/.build/index-profile/$LABEL"
[ ! -e "$OUT" ] || { echo 'Choose a fresh label; previous evidence will not be overwritten' >&2; exit 2; }
mkdir -p "$OUT"
ADB=(adb)
if [ -n "${ANDROID_SERIAL:-}" ]; then ADB+=(-s "$ANDROID_SERIAL"); fi
APP=org.openoffline.translator.android
FLASH=true
ARGS=("$@")
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 3 ] && [ "$1" = -e ] || { echo 'Expected -e KEY VALUE arguments' >&2; exit 2; }
  if [ "$2" = flash ]; then FLASH="$3"; fi
  shift 3
done
[[ "$FLASH" = true || "$FLASH" = false ]] || { echo 'flash must be true or false' >&2; exit 2; }
"${ADB[@]}" get-state
"${ADB[@]}" install -r apps/android/app/build/outputs/apk/debug/app-debug.apk
"${ADB[@]}" install -r apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
"${ADB[@]}" shell dumpsys thermalservice > "$OUT/thermal-before.txt"
"${ADB[@]}" shell rm -f "/sdcard/Android/data/$APP/files/index-vulkan-$FLASH.json"
python3 scripts/android/thermal_control.py --out "$OUT/thermal-guard" --stop-app "$APP" -- \
  "${ADB[@]}" shell am instrument -w -r -e class "$APP.IndexGpuTest" "${ARGS[@]}" "$APP.test/androidx.test.runner.AndroidJUnitRunner"
ATTEMPT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["acceptedAttempt"])' "$OUT/thermal-guard/result.json")"
cp "$OUT/thermal-guard/attempt-$ATTEMPT.log" "$OUT/test.log"
"${ADB[@]}" pull "/sdcard/Android/data/$APP/files/index-vulkan-$FLASH.json" "$OUT/report.json"
"${ADB[@]}" shell dumpsys thermalservice > "$OUT/thermal-after.txt"
# Native stderr is internal (0600); use the debuggable app's uid, not shared storage.
if python3 - "$OUT/report.json" <<'PY'
import json,sys
sys.exit(json.load(open(sys.argv[1])).get('profile','none') == 'none')
PY
then
  "${ADB[@]}" exec-out run-as "$APP" cat files/index-profile.log > "$OUT/profile.log"
  python3 scripts/android/summarize-gpu-profile.py "$OUT/profile.log" > "$OUT/summary.json"
fi
grep -q 'OK (1 test)' "$OUT/test.log"
python3 - "$OUT/report.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
assert report['passed'], report
print('Passed:', sys.argv[1])
print('Translation seconds:', [round(row['seconds'],4) for row in report['cases']])
if report.get('corpus'):
    print('Corpus seconds:', {row['id']:round(row['seconds'],4) for row in report['corpus']})
PY
