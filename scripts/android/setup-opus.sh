#!/bin/bash
set -euo pipefail
KAT_OPUS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KAT_CT2="$KAT_OPUS_ROOT/Dependencies/vendor/CTranslate2"
KAT_SPM="$KAT_OPUS_ROOT/Dependencies/vendor/sentencepiece"
if [ ! -d "$KAT_CT2" ]; then git clone --depth 1 --branch v4.6.0 https://github.com/OpenNMT/CTranslate2.git "$KAT_CT2"; fi
if [ ! -d "$KAT_SPM" ]; then git clone --depth 1 --branch v0.2.1 https://github.com/google/sentencepiece.git "$KAT_SPM"; fi
[ "$(git -C "$KAT_CT2" rev-parse HEAD)" = 617405f4b050e994e829d527da6caa0e0030afe7 ]
[ "$(git -C "$KAT_SPM" rev-parse HEAD)" = 31646a467d2051eb904e0b45de3a73e91fe1c1e3 ]
git -C "$KAT_CT2" submodule update --init --recursive --depth 1 third_party/spdlog third_party/ruy
if git -C "$KAT_CT2" apply --check "$KAT_OPUS_ROOT/shared/native/OpusRuntime/mobile-cancel.patch" 2>/dev/null; then
    git -C "$KAT_CT2" apply "$KAT_OPUS_ROOT/shared/native/OpusRuntime/mobile-cancel.patch"
else
    git -C "$KAT_CT2" apply --reverse --check "$KAT_OPUS_ROOT/shared/native/OpusRuntime/mobile-cancel.patch"
fi
