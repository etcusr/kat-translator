#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KAT_ROOT"
ADB=(adb)
if [ -n "${ANDROID_SERIAL:-}" ]; then ADB+=(-s "$ANDROID_SERIAL"); fi
"${ADB[@]}" get-state
OUT="$KAT_ROOT/.build/android-device/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
APP=org.openoffline.translator.android
MODEL=/sdcard/Android/data/$APP/files/Index-Translate-9B.Q4_K_M.gguf
SHA=9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713
"${ADB[@]}" install -r apps/android/app/build/outputs/apk/debug/app-debug.apk
"${ADB[@]}" shell am start -n "$APP/.MainActivity"
if ! "${ADB[@]}" shell sha256sum "$MODEL" | grep -q "^$SHA "; then
  "${ADB[@]}" push model-store/blobs/sha256/$SHA "$MODEL.partial"
  "${ADB[@]}" shell sha256sum "$MODEL.partial" | grep -q "^$SHA "
  "${ADB[@]}" shell mv "$MODEL.partial" "$MODEL"
fi
"${ADB[@]}" install -r apps/android/inference/build/outputs/apk/androidTest/debug/inference-debug-androidTest.apk
"${ADB[@]}" shell am instrument -w -e class org.openoffline.translator.inference.NativeBoundaryTest,org.openoffline.translator.inference.MediaNativeBoundaryTest org.openoffline.translator.inference.test/androidx.test.runner.AndroidJUnitRunner | tee "$OUT/boundary.txt"
grep -q 'OK (7 tests)' "$OUT/boundary.txt"
"${ADB[@]}" install -r apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
# Separate guarded processes prevent one long continuous inference workload.
# Every retry has its own log; only the accepted attempt enters index.txt.
for TEST in WorkspaceNavigationTest IndexDeviceTest IndexGpuTest IndexScreenTest; do
  GUARD="$OUT/$TEST-thermal"
  python3 scripts/android/thermal_control.py --out "$GUARD" --stop-app "$APP" -- \
    "${ADB[@]}" shell am instrument -w -e class "$APP.$TEST" "$APP.test/androidx.test.runner.AndroidJUnitRunner"
  ATTEMPT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["acceptedAttempt"])' "$GUARD/result.json")"
  # am instrument may exit zero even when JUnit failed or the app crashed.
  grep -Eq '^OK \([1-9][0-9]* tests?\)' "$GUARD/attempt-$ATTEMPT.log"
  cat "$GUARD/attempt-$ATTEMPT.log" >> "$OUT/index.txt"
done
"${ADB[@]}" pull "/sdcard/Android/data/$APP/files/index-acceptance.json" "$OUT/report.json"
"${ADB[@]}" pull "/sdcard/Android/data/$APP/files/ui-acceptance.json" "$OUT/ui-report.json"
"${ADB[@]}" pull "/sdcard/Android/data/$APP/files/index-vulkan-true.json" "$OUT/gpu-report.json"
python3 - "$OUT/report.json" <<'PY'
import json,sys
with open(sys.argv[1]) as f:report=json.load(f)
assert report['passed'],report
print('Real Index acceptance passed:',sys.argv[1])
PY
