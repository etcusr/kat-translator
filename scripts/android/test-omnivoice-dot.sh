#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KAT_ROOT"
mkdir -p .build/android-media
OV_GGML="$KAT_ROOT/Dependencies/vendor/omnivoice-mobile/ggml"
/usr/bin/clang++ -std=c++17 -O2 -mcpu=generic -march=armv8-a -DGGML_MAX_NAME=128 \
 -I"$OV_GGML/include" -I"$OV_GGML/src" -I"$OV_GGML/src/ggml-cpu" \
 -Iapps/android/inference/src/main/cpp scripts/android/native/omnivoice_dot_test.cpp \
 -o .build/android-media/omnivoice-dot-test
.build/android-media/omnivoice-dot-test
