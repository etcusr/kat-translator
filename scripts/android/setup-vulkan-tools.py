#!/usr/bin/env python3
"""Install pinned host shader compiler/headers in the project's local tool cache (macOS arm64)."""
import concurrent.futures,hashlib,json,tarfile,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parents[2]/'.build/android-tools/vulkan'
root.mkdir(parents=True,exist_ok=True)
packages={
 'shaderc':('2026.4','12ba0c59a98fb8f671f9473573002b2a812f26d2e60ea4f577f0c8c750c9838a'),
 'spirv-headers':('1.4.363.0','281120edad71f06ccd2fb24cd1476382311664cfd914ee45380a336d58a4e157'),
 'vulkan-headers':('1.4.363.0','e29460a3bc874e18e407211f3e550cf60177c6f7614c04d3081beb94d8ad4ab2'),
}
def install(row):
 name,(version,sha)=row
 archive=root/(name+'.tar.gz')
 if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=sha:
  token=json.load(urllib.request.urlopen(f'https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/{name}:pull'))['token']
  req=urllib.request.Request(f'https://ghcr.io/v2/homebrew/core/{name}/blobs/sha256:{sha}',headers={'Authorization':'Bearer '+token})
  with urllib.request.urlopen(req,timeout=60) as response, archive.open('wb') as out:
   while chunk:=response.read(1024*1024):out.write(chunk)
 assert hashlib.sha256(archive.read_bytes()).hexdigest()==sha, name+' checksum mismatch'
 with tarfile.open(archive) as tar:
  for member in tar.getmembers():
   assert not member.name.startswith('/') and '..' not in Path(member.name).parts
  tar.extractall(root,filter='data')
 print(name,version,'verified',flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(install,packages.items()))
