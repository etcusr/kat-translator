#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
python3 "$KAT_ROOT/scripts/generate-model-catalog.py" --check
python3 "$KAT_ROOT/scripts/android/generate-ui-catalog.py" --check
[ "$(git -C "$KAT_ROOT/Dependencies/vendor/llama.cpp" rev-parse HEAD)" = d81235049384534c167caea52b85a694f6103d14 ]
cd "$KAT_ROOT/apps/android"
./gradlew --no-daemon testDebugUnitTest lintDebug assembleDebug assembleDebugAndroidTest "$@"
