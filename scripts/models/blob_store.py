#!/usr/bin/env python3
"""Adopt an existing local weight with no duplicate data blocks. No downloads."""
import argparse,hashlib,os,re
from pathlib import Path

def verify(path,sha,size):
    if path.stat().st_size!=size:raise ValueError('Size mismatch: '+str(path))
    with path.open('rb') as stream:
        if hashlib.file_digest(stream,'sha256').hexdigest()!=sha:raise ValueError('SHA-256 mismatch: '+str(path))

def adopt(source:Path,store:Path,sha:str,size:int)->Path:
    if not re.fullmatch('[a-f0-9]{64}',sha) or size<=0:raise ValueError('Invalid descriptor')
    source=source.parent.resolve()/source.name;store=store.resolve();verify(source,sha,size)
    store.mkdir(parents=True,exist_ok=True);target=store/sha
    if target.exists():verify(target,sha,size)
    else:
        # Atomic create, no replacement and no copy fallback across filesystems.
        try:os.link(source.resolve(),target)
        except FileExistsError:verify(target,sha,size)
    if source.resolve()==target:return target
    temporary=source.with_name(source.name+'.blob-link')
    try:
        temporary.symlink_to(os.path.relpath(target,source.parent))
        temporary.replace(source)
    finally:
        if temporary.is_symlink():temporary.unlink()
    return target

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('--store',type=Path,default=Path('model-store/blobs/sha256'));p.add_argument('--sha256',required=True);p.add_argument('--bytes',type=int,required=True);a=p.parse_args()
    print(adopt(a.source,a.store,a.sha256,a.bytes))
