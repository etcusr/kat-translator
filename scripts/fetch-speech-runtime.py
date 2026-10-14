#!/usr/bin/env python3
"""Fetch checksum-pinned Apple speech runtime binaries, never speech recordings."""
import hashlib, pathlib, urllib.request, zipfile
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'Dependencies' / 'build' / 'speech'
DOWNLOADS = ROOT / 'Dependencies' / 'downloads'
FILES = [
 ('sherpa-ios.zip', 'https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-ios-static.xcframework.zip', '6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de'),
 ('onnx-ios.zip', 'https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.1/onnxruntime-ios-static-xcframework-1.28.1.xcframework.zip', '992d8a0cc6014cccc3a7815c36bbff5e5a06833ea2c4d47dd43ef071f639cf9d'),
 ('silero_vad.onnx', 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx', '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6')]
OUT.mkdir(parents=True, exist_ok=True); DOWNLOADS.mkdir(parents=True, exist_ok=True)
for name, url, digest in FILES:
    path = DOWNLOADS / name
    if not path.exists(): urllib.request.urlretrieve(url, path)
    with path.open('rb') as stream: actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual != digest: raise RuntimeError('Checksum mismatch: ' + name)
    if name.endswith('.zip'):
        with zipfile.ZipFile(path) as archive:
            for item in archive.infolist():
                if not (OUT / item.filename).resolve().is_relative_to(OUT): raise RuntimeError('Unsafe ZIP path')
            archive.extractall(OUT)
    else: (OUT / name).write_bytes(path.read_bytes())
    print(name, 'verified', flush=True)
