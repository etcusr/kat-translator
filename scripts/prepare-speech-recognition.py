#!/usr/bin/env python3
"""Pinned production Swift ASR runtimes; public sources, no account credentials."""
from pathlib import Path
import subprocess, os
root = Path(__file__).resolve().parent.parent
vendor = root/'Dependencies/vendor'; vendor.mkdir(parents=True,exist_ok=True)
for name,remote,revision in [('FluidAudio','https://github.com/FluidInference/FluidAudio.git','ea63ac36fcadb8a6611d0f58a8e4a0e7dd4381e2')]:
    repo=vendor/name
    if not repo.exists():
        cached=root/'.build/asr-comparison'/name
        subprocess.run(['git','-c','credential.helper=','clone',str(cached) if cached.exists() else remote,str(repo)],env=os.environ|{'GIT_TERMINAL_PROMPT':'0'},check=True)
    subprocess.run(['git','-C',str(repo),'checkout','--detach',revision],check=True)
    if name=='FluidAudio':
        text=subprocess.check_output(['git','-C',str(repo),'show',revision+':Package@swift-6.2.swift'],text=True)
        start=text.index('        .binaryTarget(');end=text.index('        .target(',start)
        text=text[:start]+text[end:]
        text=text.replace('                .target(name: "NemoTextProcessing", condition: .when(traits: ["NemoTextProcessing"])),\n','').replace('.default(enabledTraits: ["NemoTextProcessing"])','.default(enabledTraits: [])')
    (repo/'Package@swift-6.2.swift').write_text(text)
