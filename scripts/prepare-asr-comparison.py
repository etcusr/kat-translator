#!/usr/bin/env python3
"""Prepare pinned, optional developer ASR probe; no production dependency changes."""
from pathlib import Path
import subprocess, urllib.request, json, hashlib, os
root = Path(__file__).resolve().parent.parent
work = root / '.build/asr-comparison'
work.mkdir(parents=True, exist_ok=True)
revision = 'ea63ac36fcadb8a6611d0f58a8e4a0e7dd4381e2'
repo = work / 'FluidAudio'
if not repo.exists():
    subprocess.run(['git', '-c', 'credential.helper=', 'clone', 'https://github.com/FluidInference/FluidAudio.git', str(repo)], env=os.environ | {'GIT_TERMINAL_PROMPT': '0'}, check=True)
subprocess.run(['git', '-C', str(repo), 'checkout', '--detach', revision], check=True)
# Omit the optional remote TTS normalizer binary entirely for this ASR-only build.
# SwiftPM may still fetch declared binary artifacts even with its trait disabled.
manifest_text = subprocess.check_output(['git', '-C', str(repo), 'show', revision+':Package@swift-6.2.swift'], text=True)
start = manifest_text.index('        .binaryTarget(')
end = manifest_text.index('        .target(', start)
manifest_text = manifest_text[:start] + manifest_text[end:]
manifest_text = manifest_text.replace('                .target(name: "NemoTextProcessing", condition: .when(traits: ["NemoTextProcessing"])),\n', '')
manifest_text = manifest_text.replace('.default(enabledTraits: ["NemoTextProcessing"])', '.default(enabledTraits: [])')
repo.joinpath('Package@swift-6.2.swift').write_text(manifest_text)
support = work / 'ProbeSupport'
(support/'Sources/ASRProbeSupport').mkdir(parents=True, exist_ok=True)
(support/'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ASRProbeSupport", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "ASRProbeSupport", targets: ["ASRProbeSupport"])], dependencies: [.package(path: "../FluidAudio", traits: [])], targets: [.target(name: "ASRProbeSupport", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])])
''')
(support/'Sources/ASRProbeSupport/Export.swift').write_text('@_exported import FluidAudio\n')
manifest = json.loads((root/'docs/benchmarks/asr-comparison/parakeet-manifest.json').read_text())
model = work/'parakeet-tdt-0.6b-v3-coreml'
for entry in manifest['files']:
    path = model/entry['path']
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
        print('Downloading', entry['path'], flush=True)
        url = 'https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/'+manifest['revision']+'/'+entry['path']
        partial = path.with_suffix(path.suffix+'.partial')
        urllib.request.urlretrieve(url, partial)
        if partial.stat().st_size != entry['bytes'] or hashlib.sha256(partial.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('Verification failed: '+entry['path'])
        partial.replace(path)
print('Ready:', model)
