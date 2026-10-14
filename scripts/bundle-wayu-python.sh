#!/bin/bash
set -euo pipefail
# Python's official Apple-support packaging converts extension modules to signed
# frameworks. The interpreter and all executable Python sources ship in the app.
export EXPANDED_CODE_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
export PROJECT_DIR="${KAT_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Ad-Hoc}"
cd "$PROJECT_DIR"
source "$PROJECT_DIR/Dependencies/build/wayu/Python.xcframework/build/utils.sh"
install_python Dependencies/build/wayu/Python.xcframework
rsync -a --delete --exclude '__pycache__' "$PROJECT_DIR/Dependencies/build/wayu/WayuPython/" "$CODESIGNING_FOLDER_PATH/WayuPython/"
