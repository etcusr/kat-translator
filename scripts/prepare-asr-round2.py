#!/usr/bin/env python3
"""Reproduce round-two ASR dependencies and verified weights (developer build only)."""
from pathlib import Path
import subprocess, os, json, hashlib, urllib.request
root = Path(__file__).resolve().parent.parent
subprocess.run(['python3', str(root/'scripts/prepare-speech-recognition.py')], check=True)
work = root/'.build/asr-comparison'
repo = work/'SpeechSwift'
revision = 'cbcdfc6be5e723952d29ab6e32af5e22ad8e70fa'
if not repo.exists():
    subprocess.run(['git', '-c', 'credential.helper=', 'clone', 'https://github.com/soniqo/speech-swift.git', str(repo)], env=os.environ | {'GIT_TERMINAL_PROMPT':'0'}, check=True)
subprocess.run(['git', '-C', str(repo), 'checkout', '--detach', revision], check=True)
# ASR-only manifest: omit unrelated TTS/server packages. Source is unchanged.
(repo/"Package.swift").write_text('// swift-tools-version: 5.10\nimport PackageDescription\nlet package = Package(name: "Qwen3Speech", platforms: [.iOS("18.0"), .macOS("15.0")], products: [.library(name: "Qwen3ASR", targets: ["Qwen3ASR"])], dependencies: [.package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"), .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.4")], targets: [\n.target(name: "AudioCommon", dependencies: [.product(name: "Hub", package: "swift-transformers")]),\n.target(name: "MLXCommon", dependencies: ["AudioCommon", .product(name: "MLX", package: "mlx-swift"), .product(name: "MLXNN", package: "mlx-swift"), .product(name: "MLXFast", package: "mlx-swift"), .product(name: "MLXFFT", package: "mlx-swift")]),\n.target(name: "SpeechVAD", dependencies: ["AudioCommon", "MLXCommon", .product(name: "MLX", package: "mlx-swift"), .product(name: "MLXNN", package: "mlx-swift")]),\n.target(name: "Qwen3ASR", dependencies: ["AudioCommon", "MLXCommon", "SpeechVAD", .product(name: "MLX", package: "mlx-swift"), .product(name: "MLXNN", package: "mlx-swift"), .product(name: "MLXFast", package: "mlx-swift")])])\n')
(work/"ProbeSupport/Package.swift").write_text('// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: "ASRProbeSupport", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "ASRProbeSupport", targets: ["ASRProbeSupport"])], dependencies: [.package(path: "../../../shared/packages/SpeechRecognitionRuntime"), .package(path: "../SpeechSwift")], targets: [.target(name: "ASRProbeSupport", dependencies: [.product(name: "SpeechRecognitionRuntime", package: "SpeechRecognitionRuntime"), .product(name: "Qwen3ASR", package: "SpeechSwift")])])\n')
(work/"ProbeSupport/Sources/ASRProbeSupport/Export.swift").write_text('@_exported import SpeechRecognitionRuntime\n@_exported import Qwen3ASR\n')

def digest(path):
    with path.open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()
for name, folder in [('ultra','parakeet-ultra-coreml'), ('nemotron','nemotron-multilingual-2240'), ('qwen','qwen3-asr-06b')]:
    manifest=json.loads((root/f'docs/benchmarks/asr-round2/{name}-manifest.json').read_text())
    for entry in manifest['files']:
        p=work/folder/entry['path'];p.parent.mkdir(parents=True,exist_ok=True)
        if p.exists() and p.stat().st_size==entry['bytes'] and digest(p)==entry['sha256']: continue
        partial=p.with_suffix(p.suffix+'.partial')
        print('Downloading', name, entry['path'], flush=True)
        urllib.request.urlretrieve('https://huggingface.co/'+manifest['repo']+'/resolve/'+manifest['revision']+'/'+entry['source'], partial)
        if partial.stat().st_size!=entry['bytes'] or digest(partial)!=entry['sha256']:raise ValueError('Hash mismatch: '+str(p))
        partial.replace(p)
print('All round-two models and packages ready.')
