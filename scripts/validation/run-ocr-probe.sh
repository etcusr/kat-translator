#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
probe_python="${OCR_PROBE_PYTHON:-$PWD/.build/ocr-probe/venv/bin/python}"
probe_root="$PWD/.build/ocr-probe"
probe_runtime="$($probe_python -c 'import onnxruntime,pathlib; print(pathlib.Path(onnxruntime.__file__).parent/"capi")')"
probe_header="$PWD/Dependencies/build/speech/onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Headers"
mkdir -p "$probe_root/include/onnxruntime" "$probe_root/OCRProbe.app/Contents/MacOS" "$probe_root/OCRProbe.app/Contents/Resources"
if ! test "$probe_header/onnxruntime_c_api.h" -ef "$probe_root/include/onnxruntime/onnxruntime_c_api.h"; then
    cp "$probe_header/onnxruntime_c_api.h" "$probe_root/include/onnxruntime/"
fi
# The pip dylib has a major-version install name without a matching symlink.
probe_library="$(find "$probe_runtime" -name 'libonnxruntime.*.*.dylib' -maxdepth 1 | head -1)"
test -n "$probe_library"
ln -sf "$probe_library" "$probe_root/libonnxruntime.1.dylib"
clang -dynamiclib shared/native/app/Camera/OCRRuntime.c -I "$probe_root/include" "$probe_library" -Wl,-rpath,"$probe_root" -o "$probe_root/libocr.dylib"
"$probe_python" scripts/validation/ocr-probe.py
cp assets/bundled/OCR/*.json "$probe_root/OCRProbe.app/Contents/Resources/"
cat > "$probe_root/OCRProbe.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>OCRProbe</string><key>CFBundleIdentifier</key><string>org.openoffline.ocrprobe</string></dict></plist>
PLIST
swift build --package-path shared/packages/OfflineCore --scratch-path .build/core
swiftc -parse-as-library -I .build/core/out/Products/Debug \
-Xcc -fmodule-map-file=.build/core/out/Intermediates.noindex/GeneratedModuleMaps/ArchiveRuntime.modulemap \
-import-objc-header shared/native/app/Camera/OCRRuntime.h shared/apple/Camera/HybridOCR.swift scripts/validation/ocr-hybrid-probe.swift \
.build/core/out/Products/Debug/libOfflineCore.a "$probe_root/libocr.dylib" -lbz2 \
-o "$probe_root/OCRProbe.app/Contents/MacOS/OCRProbe"
"$probe_root/OCRProbe.app/Contents/MacOS/OCRProbe"
