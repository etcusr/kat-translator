#!/usr/bin/env python3
"""Bundle and relocate all non-system runtime dependencies; destination needs no Python/Homebrew."""
from pathlib import Path
import subprocess, shutil, sys, os, runpy
root=Path(__file__).resolve().parent.parent
mac_profile=runpy.run_path(str(root/'scripts/mac-build-profile.py'))['profile'](os.environ.get('KAT_MAC_PROFILE','modern'))
contents=Path(sys.argv[1]); fw=contents/'Frameworks';res=contents/'Resources'
fw.mkdir(parents=True,exist_ok=True);res.mkdir(parents=True,exist_ok=True)
# Mac App Store build (sandboxed): ship no TLS/crypto libraries. Downloads use URLSession,
# Index/OPUS workers load local files only (index_mlx.py stubs ssl for import-time use).
store_sandbox=os.environ.get('ENABLE_APP_SANDBOX') == 'YES'
STORE_OMIT_DYNLOAD=('_ssl','_hashlib')
STORE_OMIT_INDEX=('hf_xet',)
def copyfile(a,b):
 if b.exists(): b.chmod(b.stat().st_mode | 0o200)
 shutil.copy2(a,b)
def copytree(a,b):
 b.mkdir(parents=True,exist_ok=True)
 # Do not copy protected provenance xattrs onto an already signed build product.
 excludes=['__pycache__','*.pyc','site-packages','test','tests','idlelib','tkinter','ensurepip','config-*-darwin']
 subprocess.run(['rsync','-aL','--chmod=u+w',*[arg for item in excludes for arg in ('--exclude',item)],str(a)+'/',str(b)+'/'],check=True)
py=Path('/opt/homebrew/opt/python@3.11/Frameworks/Python.framework/Versions/3.11')
py_library=py/'Python'
if mac_profile['suffix']:
 py=root/'Dependencies/build/macos15/StandalonePython/python'
 py_library=py/'lib/libpython3.11.dylib'
 # Drop libraries/extensions retained by an earlier host-Python build.
 if (res/'python').exists(): shutil.rmtree(res/'python')
 for previous in fw.glob('*.dylib'): previous.unlink()
copytree(py/'lib/python3.11',res/'python/lib/python3.11')
for extension in (res/'python/lib/python3.11/lib-dynload').glob('_tkinter*.so'):
 extension.unlink()  # GUI toolkit is unused; do not carry its optional dependencies.
# Build configuration archives contain host framework links, never needed by the frontend.
for config in (res/'python/lib/python3.11').glob('config-*-darwin'):
 if config.is_dir(): shutil.rmtree(config)
if store_sandbox:
 for extension in (res/'python/lib/python3.11/lib-dynload').glob('*.so'):
  if extension.name.split('.')[0] in STORE_OMIT_DYNLOAD: extension.unlink()
 for stale in ('libssl.3.dylib','libcrypto.3.dylib'):
  if (fw/stale).exists(): (fw/stale).unlink()
copytree(root/'Dependencies/build/wayu/WayuPython',res/'WayuPython')
index_source=root/'Dependencies/build'/mac_profile['runtime']/'IndexPython'
if not index_source.is_dir(): raise RuntimeError('Prepare Index runtime: python3 scripts/prepare-index-mlx.py')
copytree(index_source,res/'IndexPython')
if store_sandbox:
 # SwiftPM resource bundles carry no executable but arrive development-signed; export does
 # not re-sign inside Resources (ITMS-90284). The app signature seals them as resources.
 for resource_bundle in res.glob('*.bundle'):
  info=resource_bundle/'Contents/Info.plist'
  if info.exists() and b'CFBundleExecutable' not in info.read_bytes() and (resource_bundle/'Contents/_CodeSignature').exists():
   shutil.rmtree(resource_bundle/'Contents/_CodeSignature')
 for omitted in res.glob('IndexPython/*'):
  if omitted.name.split('-')[0] in STORE_OMIT_INDEX: shutil.rmtree(omitted)
shutil.copy2(root/'shared/native/IndexMLX/index_mlx.py',res/'IndexPython/index_mlx.py')
opus_source=root/'Dependencies/build/opus-gpu/OpusPython'
if not opus_source.is_dir(): raise RuntimeError('Prepare OPUS GPU runtime: python3 scripts/prepare-opus-gpu.py')
copytree(opus_source,res/'OpusPython')
# Store validation requires every executable to be sandboxed. protoc is never run, so the
# store build omits it; `import torch` requires torch_shm_manager to exist, so it stays and is
# signed like the helper (sandbox + inherit).
shm_manager=res/'OpusPython/torch/bin/torch_shm_manager'
if store_sandbox:
 for tool in (res/'OpusPython/torch/bin').glob('protoc*'): tool.unlink()
shutil.copy2(root/'shared/native/OpusGPU/opus_gpu.py',res/'OpusPython/opus_gpu.py')
helper_source=py/'bin/python3.11'
framework_executable=py/'Resources/Python.app/Contents/MacOS/Python'
if framework_executable.exists(): helper_source=framework_executable
helper=contents/'MacOS/OpusPython'
copyfile(helper_source,helper)
subprocess.run(['rsync','-a',str(root/'Dependencies/build/omnivoice/OmniVoiceRuntime.xcframework/macos-arm64/OmniVoiceRuntime.framework')+'/',str(fw/'OmniVoiceRuntime.framework')+'/'],check=True)
subprocess.run(['rsync','-a',str(root/'Dependencies/build/opus/OpusRuntime.xcframework/macos-arm64/OpusRuntime.framework')+'/',str(fw/'OpusRuntime.framework')+'/'],check=True)
inputs=[(root/'Dependencies/build/macos/libTranslationRuntime.dylib','libTranslationRuntime.dylib'),(root/'Dependencies/build/speech-macos/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx-c-api.dylib','libsherpa-onnx-c-api.dylib'),(root/'.build/wayu-env/lib/python3.11/site-packages/onnxruntime/capi/libonnxruntime.1.30.0.dylib','libonnxruntime.dylib'),(py_library,'libpython3.11.dylib')]
queue=[];known={}
for src,name in inputs:
 copyfile(src,fw/name);queue.append((src,fw/name));known[str(src.resolve())]=name
# Python extensions need their original absolute dependencies rewritten too.
queue += [(py/'lib/python3.11/lib-dynload'/p.name,p) for p in (res/'python/lib/python3.11/lib-dynload').glob('*.so')]
for source in index_source.rglob('*'):
 if store_sandbox and source.relative_to(index_source).parts[0].split('-')[0] in STORE_OMIT_INDEX: continue
 if source.is_file() and source.suffix in {'.so','.dylib'}:
  queue.append((source,res/'IndexPython'/source.relative_to(index_source)))
queue += [(fw/'OmniVoiceRuntime.framework/OmniVoiceRuntime',fw/'OmniVoiceRuntime.framework/OmniVoiceRuntime')]
queue += [(fw/'OpusRuntime.framework/OpusRuntime',fw/'OpusRuntime.framework/OpusRuntime')]
queue.append((helper_source,helper))
for source in opus_source.rglob('*'):
 if store_sandbox and source.relative_to(opus_source).parts[:2] == ('torch','bin') and source.name.startswith('protoc'): continue
 if source.is_file():
  with source.open('rb') as stream: magic=stream.read(4)
  if magic in {bytes.fromhex(x) for x in ('cffaedfe','feedfacf','cafebabe','bebafeca')}:
   queue.append((source,res/'OpusPython'/source.relative_to(opus_source)))
seen=set()
while queue:
 src,dst=queue.pop(0)
 if str(dst) in seen: continue
 seen.add(str(dst));os.chmod(dst,0o755)
 subprocess.run(['codesign','--remove-signature',str(dst)],capture_output=True)
 # Native MLX wheels/kernels must resolve only from this app, not the lab or Homebrew.
 commands=subprocess.check_output(['otool','-l',str(dst)],text=True)
 if dst == helper and '@executable_path/../Frameworks' not in commands:
  subprocess.run(['install_name_tool','-add_rpath','@executable_path/../Frameworks',str(dst)],check=True)
 import re
 for rpath in re.findall(r'cmd LC_RPATH\n.*?\n\s*path (.*?) \(offset',commands):
  if rpath.startswith('/') and not rpath.startswith(('/System/','/usr/lib/')):
   subprocess.run(['install_name_tool','-delete_rpath',rpath,str(dst)],check=True)
 deps=subprocess.check_output(['otool','-L',str(src)],text=True).splitlines()[1:]
 install_ids=subprocess.check_output(['otool','-D',str(src)],text=True).splitlines()[1:]
 if dst.suffix=='.dylib': subprocess.run(['install_name_tool','-id','@rpath/'+dst.name,str(dst)],check=True)
 for line in deps:
  dep=line.strip().split(' (')[0]
  if dep in install_ids: continue
  if not dep.startswith('/') or dep.startswith(('/System/','/usr/lib/')): continue
  resolved=str(Path(dep).resolve())
  # Preserve the liblzma ABI while avoiding the host library's macOS27 floor.
  dependency_source=Path(dep)
  if mac_profile['suffix'] and dependency_source.name.startswith('liblzma.'):
   dependency_source=root/'Dependencies/build/macos15/liblzma.5.dylib'
   if not dependency_source.is_file():raise RuntimeError('Prepare macOS15 liblzma first')
  if resolved==str(src.resolve()): continue
  if resolved in known: name=known[resolved]
  else:
   name=Path(dep).name
   if name in known.values(): raise RuntimeError('Duplicate runtime name '+name)
   known[resolved]=name;copyfile(dependency_source,fw/name);queue.append((dependency_source,fw/name))
  subprocess.run(['install_name_tool','-change',dep,'@rpath/'+name,str(dst)],check=True)
 # Original ONNX install name is versioned; consumers and library use stable bundle name.
 if dst.name=='libonnxruntime.dylib': subprocess.run(['install_name_tool','-id','@rpath/libonnxruntime.dylib',str(dst)],check=True)
 # A sandboxed store app may only contain executables that inherit its sandbox.
 helper_entitlements=['--entitlements',str(root/'apps/macos/KatMacHelper.entitlements')] if dst in (helper,shm_manager) and store_sandbox else []
 subprocess.run(['codesign','--force','--sign',os.environ.get('EXPANDED_CODE_SIGN_IDENTITY') or '-',*helper_entitlements,str(dst)],check=True,capture_output=True)
subprocess.run(['codesign','--force','--sign',os.environ.get('EXPANDED_CODE_SIGN_IDENTITY') or '-',str(fw/'OmniVoiceRuntime.framework')],check=True,capture_output=True)
subprocess.run(['codesign','--force','--sign',os.environ.get('EXPANDED_CODE_SIGN_IDENTITY') or '-',str(fw/'OpusRuntime.framework')],check=True,capture_output=True)

# Declare repackaged SDKs after all runtime copies, before the app is signed.
subprocess.run([sys.executable, str(root/"scripts/install-sdk-privacy-manifests.py"),
                "--platform", "macos", "--app", str(contents.parent)], check=True)
