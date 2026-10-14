#!/bin/bash
# Device acceptance for portable iOS features. Install the APKs and exact shared
# fixtures first; this runner never downloads models or replaces Index weights.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KAT_ROOT"
ADB=(adb)
if [ -n "${ANDROID_SERIAL:-}" ]; then ADB+=(-s "$ANDROID_SERIAL"); fi
GROUP="${1:-ui}"
case "$GROUP" in
  ui) TESTS=(WorkspaceNavigationTest ProductInteractionTest SettingsParityTest MenuNavigationTest LauncherIconTest) ;;
  contracts) TESTS=(WayuDeviceTest MediaLanguageDeviceTest AudioImportTest) ;;
  media) TESTS=('MediaPipelineTest#piper' 'MediaPipelineTest#supertonic' 'MediaPipelineTest#wayu' 'MediaPipelineTest#omniVoice' 'MediaPipelineTest#asr' 'MediaPipelineTest#ocr') ;;
  opus) TESTS=(OpusDeviceTest) ;;
  downloads) TESTS=(PackageDownloadServiceTest) ;;
  transfers) TESTS=(packages.PackageRepositoryLifecycleTest) ;;
  camera) TESTS=(camera.CameraPixelsDeviceTest camera.LiveCameraDeviceTest) ;;
  voice) TESTS=(VoiceImportFlowTest) ;;
  cancel) TESTS=(ProcessingCancellationTest SpeechCancellationTest) ;;
  recording) TESTS=(RecordingControlsTest HoldRecordingGestureTest) ;;
  default) TESTS=(OpusDefaultFlowTest) ;;
  photo) TESTS=(FrozenPhotoFlowTest) ;;
  *) echo 'Usage: test-parity.sh {ui|contracts|media|opus|downloads|transfers|camera|voice|cancel|recording|default|photo}' >&2; exit 2 ;;
esac
APP=org.openoffline.translator.android
OUT="$KAT_ROOT/.build/android-parity-device/${GROUP}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
"${ADB[@]}" get-state
cleanup_preferences() {
  # Force-stopping a hot test skips JUnit finally blocks. This tiny cleanup does
  # not launch the UI or an inference model and preserves the thermal marker.
  "${ADB[@]}" shell am instrument -w -e class "$APP.TestPreferenceRecovery" \
    "$APP.test/androidx.test.runner.AndroidJUnitRunner" > "$OUT/preference-recovery.log" 2>&1
}
trap cleanup_preferences EXIT
for TEST in "${TESTS[@]}"; do
  GUARD="$OUT/${TEST//#/-}"
  if [ "${KAT_THERMAL_GUARD:-0}" = 1 ]; then
    python3 scripts/android/thermal_control.py --out "$GUARD" --stop-app "$APP" -- \
      "${ADB[@]}" shell am instrument -w -e class "$APP.$TEST" "$APP.test/androidx.test.runner.AndroidJUnitRunner"
    ATTEMPT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["acceptedAttempt"])' "$GUARD/result.json")"
    LOG="$GUARD/attempt-$ATTEMPT.log"
  else
    # User requested uninterrupted functional acceptance after thermal testing.
    # Opt in explicitly for comparable performance measurements in future.
    mkdir -p "$GUARD"
    LOG="$GUARD/functional.log"
    "${ADB[@]}" shell am instrument -w -e class "$APP.$TEST" "$APP.test/androidx.test.runner.AndroidJUnitRunner" > "$LOG" 2>&1
  fi
  cat "$LOG"
  # Android's instrumentation shell can return zero for test failures/crashes.
  if ! grep -Eq '^OK \([1-9][0-9]* tests?\)' "$LOG" || grep -Eq 'FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed' "$LOG"; then
    echo "Device acceptance failed: $TEST; evidence: $LOG" >&2
    exit 1
  fi
done
echo "Device acceptance passed: $GROUP; evidence: $OUT"
