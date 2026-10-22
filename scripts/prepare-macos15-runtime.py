#!/usr/bin/env python3
"""Prepare the compatible binary runtime and the pinned standalone Python without downloading model weights.

Every downloaded archive is pinned by URL and SHA-256 in this file (not taken from a server response),
and verification raises instead of using `assert`, so it also holds under `python -O`.
"""
from pathlib import Path
import hashlib,json,subprocess,urllib.request,zipfile,tarfile,shutil,os
root=Path(__file__).resolve().parents[1]
lab=root/'.build/macos15-release';lab.mkdir(parents=True,exist_ok=True)
PINNED={
 'mlx-metal':('mlx_metal-0.32.2-py3-none-macosx_15_0_arm64.whl',
  'https://files.pythonhosted.org/packages/79/ec/34f37376e26d537fadffb99af3a760d6545e37f5e1a30a552baadf237fc5/mlx_metal-0.32.2-py3-none-macosx_15_0_arm64.whl',
  '55a369250d220b2cf10213a87a2ac1b1a420608c5b35b1df4e7147ac8e32f121'),
 'mlx':('mlx-0.32.2-cp311-cp311-macosx_15_0_arm64.whl',
  'https://files.pythonhosted.org/packages/c4/77/a1f7b2ca95b5c5106eb00268a950e351deb3348cd5b5433861619d3b0de0/mlx-0.32.2-cp311-cp311-macosx_15_0_arm64.whl',
  'e507dc67d268cf78254e17756f25057198fe74791508fcbd1e6d967673a8d374'),
 'python':('cpython-3.11.17+20261009-aarch64-apple-darwin-install_only_stripped.tar.gz',
  'https://github.com/astral-sh/python-build-standalone/releases/download/20261009/cpython-3.11.17%2B20261009-aarch64-apple-darwin-install_only_stripped.tar.gz',
  'f58d38af4680fbf9f89c329e732b7cca1bd06ff7a93884798b27d541bee138f6'),
 'xz':('xz-5.8.4.tar.gz','https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz',
  '0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9'),
}
def fetch(key):
 name,url,sha=PINNED[key];path=lab/name
 if not path.exists():urllib.request.urlretrieve(url,path)
 actual=hashlib.sha256(path.read_bytes()).hexdigest()
 if actual!=sha:raise RuntimeError(f'{name}: SHA-256 {actual} does not match pinned {sha}')
 return path
archive=fetch('mlx-metal');core_archive=fetch('mlx');python_archive=fetch('python');xz=fetch('xz')
source=root/'Dependencies/build/index-mlx/IndexPython'
target=root/'Dependencies/build/index-mlx-macos15/IndexPython'
# Recreate from the current Index runtime every time: an older copy must never mix with new packages.
if target.exists():shutil.rmtree(target)
target.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(['cp','-cR',str(source),str(target)],check=True)
with zipfile.ZipFile(archive) as z:
 for name in z.namelist():
  if name.startswith(('mlx/','mlx_metal-')):z.extract(name,target)
shutil.copy2(root/'shared/native/IndexMLX/index_mlx.py',target/'index_mlx.py')
with zipfile.ZipFile(core_archive) as z:z.extractall(target)
python_target=root/'Dependencies/build/macos15/StandalonePython'
if not (python_target/'python/lib/libpython3.11.dylib').exists():
 python_target.mkdir(parents=True,exist_ok=True)
 with tarfile.open(python_archive) as tar:tar.extractall(python_target,filter='data')
src=lab/'xz-5.8.4'
if not src.exists():
 with tarfile.open(xz) as tar:tar.extractall(lab,filter='data')
output=root/'Dependencies/build/macos15';output.mkdir(parents=True,exist_ok=True)
library=src/'src/liblzma/.libs/liblzma.5.dylib'
if not library.is_file():
 env=dict(os.environ,MACOSX_DEPLOYMENT_TARGET='15.0',CFLAGS='-O2 -mmacosx-version-min=15.0',LDFLAGS='-mmacosx-version-min=15.0')
 with (lab/'xz-build.log').open('w') as log:
  subprocess.run([str(src/'configure'),'--disable-static','--enable-shared','--disable-xz','--disable-xzdec','--disable-lzmadec','--disable-lzmainfo','--disable-scripts','--disable-doc'],cwd=src,env=env,stdout=log,stderr=log,check=True)
  subprocess.run(['make','-j',str(os.cpu_count() or 4)],cwd=src,env=env,stdout=log,stderr=log,check=True)
shutil.copy2(library,output/'liblzma.5.dylib')
provenance={'mlxVersion':'0.32.2','wheel':PINNED['mlx-metal'][0],'wheelURL':PINNED['mlx-metal'][1],'wheelSHA256':PINNED['mlx-metal'][2],'xzVersion':'5.8.4','xzURL':PINNED['xz'][1],'xzSHA256':PINNED['xz'][2],'deploymentTarget':'15.0','modelPackage':'assets/catalogs/index-mlx-package.json','additionalModelDownloadBytes':0}
provenance.update(mlxCoreWheel=PINNED['mlx'][0],mlxCoreSHA256=PINNED['mlx'][2],pythonVersion='3.11.17',pythonArchive=PINNED['python'][0],pythonURL=PINNED['python'][1],pythonSHA256=PINNED['python'][2])
(output/'runtime-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
print('Compatible MLX, pinned standalone Python and liblzma prepared; no model download')
