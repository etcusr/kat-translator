#!/bin/bash
set -euo pipefail
# Python's official Apple-support packaging converts extension modules to signed
# frameworks. The interpreter and all executable Python sources ship in the app.
export EXPANDED_CODE_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
export PROJECT_DIR="${KAT_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Ad-Hoc}"
cd "$PROJECT_DIR"
source "$PROJECT_DIR/Dependencies/build/wayu/Python.xcframework/build/utils.sh"
install_stdlib Dependencies/build/wayu/Python.xcframework
# Strip only copied modules, including stale frameworks from incremental builds.
# Keep Python's built-in hash implementations; Wayu does not use Python TLS.
python3 "$PROJECT_DIR/scripts/prune-ios-python.py" --app "$CODESIGNING_FOLDER_PATH"
PYTHON_VER=$(basename "$(dirname "$(find "$CODESIGNING_FOLDER_PATH/python/lib" -type d -name lib-dynload)")")
process_dylibs Dependencies/build/wayu/Python.xcframework "python/lib/$PYTHON_VER/lib-dynload"
rsync -a --delete --exclude '__pycache__' "$PROJECT_DIR/Dependencies/build/wayu/WayuPython/" "$CODESIGNING_FOLDER_PATH/WayuPython/"
