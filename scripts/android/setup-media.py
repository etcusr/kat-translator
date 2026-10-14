#!/usr/bin/env python3
"""Install only pinned arm64 speech libraries and C headers into ignored build cache."""
import hashlib
import json
import pathlib
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = ROOT / '.build/android-media'
LOCK = json.loads((ROOT / 'Dependencies/android-media.lock.json').read_text())

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def download(url, relative, sha):
    path = CACHE / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and digest(path) == sha:
        return path
    temp = path.with_suffix(path.suffix + '.partial')
    with urllib.request.urlopen(url, timeout=90) as response, temp.open('wb') as out:
        while block := response.read(1024 * 1024):
            out.write(block)
    if digest(temp) != sha:
        temp.unlink()
        raise RuntimeError(f'Digest mismatch: {relative}')
    temp.replace(path)
    return path

def main():
    sherpa = LOCK['sherpa']; ort = LOCK['onnxruntime']
    archive = download(sherpa['url'], 'sherpa.tar.bz2', sherpa['sha256'])
    entries = {
        'jniLibs/arm64-v8a/libsherpa-onnx-c-api.so': sherpa['arm64CAPI_SHA256'],
        'jniLibs/arm64-v8a/libonnxruntime.so': ort['arm64SHA256'],
    }
    with tarfile.open(archive, 'r:bz2') as tar:
        for path, sha in entries.items():
            member = tar.getmember('./' + path)
            if not member.isfile() or member.size > 100_000_000:
                raise RuntimeError('Unsafe runtime archive member')
            target = CACHE / path
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.is_file() and digest(target) == sha:
                continue
            temp = target.with_suffix('.partial')
            with tar.extractfile(member) as source, temp.open('wb') as output:
                while block := source.read(1024 * 1024):
                    output.write(block)
            if digest(temp) != sha:
                raise RuntimeError('Runtime library digest mismatch')
            temp.replace(target)
    download(f"https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/{sherpa['sourceCommit']}/sherpa-onnx/c-api/c-api.h", 'include/sherpa-onnx/c-api/c-api.h', sherpa['cApiHeaderSHA256'])
    download(f"https://raw.githubusercontent.com/microsoft/onnxruntime/v{ort['headerVersion']}/include/onnxruntime/core/session/onnxruntime_c_api.h", 'include/onnxruntime/onnxruntime_c_api.h', ort['headerSHA256'])
    print('Pinned Android offline media dependencies verified')

if __name__ == '__main__':
    main()
