#!/usr/bin/env python3
"""Prepare the compatible binary runtime without downloading any model weights."""
from pathlib import Path
import hashlib,json,subprocess,urllib.request,zipfile,tarfile,shutil,os
root=Path(__file__).resolve().parents[1]
lab=root/'.build/macos15-release';lab.mkdir(parents=True,exist_ok=True)
metadata=lab/'mlx-wheel.json'
if not metadata.exists():
 data=json.load(urllib.request.urlopen('https://pypi.org/pypi/mlx-metal/0.32.2/json'))
 files=[f for f in data['urls'] if 'macosx_15_0_arm64' in f['filename']]
 if len(files)!=1:raise RuntimeError('Unexpected wheel inventory')
 metadata.write_text(json.dumps(files[0],indent=2))
wheel=json.loads(metadata.read_text());archive=lab/wheel['filename']
if not archive.exists():urllib.request.urlretrieve(wheel['url'],archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==wheel['digests']['sha256']
source=root/'Dependencies/build/index-mlx/IndexPython'
target=root/'Dependencies/build/index-mlx-macos15/IndexPython'
if not target.exists():
 target.parent.mkdir(parents=True,exist_ok=True)
 subprocess.run(['cp','-cR',str(source),str(target)],check=True)
with zipfile.ZipFile(archive) as z:
 for name in z.namelist():
  if name.startswith(('mlx/','mlx_metal-')):z.extract(name,target)
shutil.copy2(root/'shared/native/IndexMLX/index_mlx.py',target/'index_mlx.py')
core_metadata=lab/'mlx-core-wheel.json'
if not core_metadata.exists():
 data=json.load(urllib.request.urlopen('https://pypi.org/pypi/mlx/0.32.2/json'))
 files=[f for f in data['urls'] if 'cp311-cp311-macosx_15_0_arm64' in f['filename']]
 if len(files)!=1:raise RuntimeError('Unexpected MLX core wheel inventory')
 core_metadata.write_text(json.dumps(files[0],indent=2))
core=json.loads(core_metadata.read_text());core_archive=lab/core['filename']
if not core_archive.exists():urllib.request.urlretrieve(core['url'],core_archive)
assert hashlib.sha256(core_archive.read_bytes()).hexdigest()==core['digests']['sha256']
with zipfile.ZipFile(core_archive) as z:z.extractall(target)
python_metadata=lab/'python-release.json'
if not python_metadata.exists():
 data=json.load(urllib.request.urlopen('https://api.github.com/repos/astral-sh/python-build-standalone/releases/tags/20261009'))
 files=[a for a in data['assets'] if a['name']=='cpython-3.11.17+20261009-aarch64-apple-darwin-install_only_stripped.tar.gz']
 if len(files)!=1:raise RuntimeError('Unexpected standalone Python inventory')
 python_metadata.write_text(json.dumps(files[0],indent=2))
python=json.loads(python_metadata.read_text());python_archive=lab/python['name']
if not python_archive.exists():urllib.request.urlretrieve(python['browser_download_url'],python_archive)
assert 'sha256:'+hashlib.sha256(python_archive.read_bytes()).hexdigest()==python['digest']
python_target=root/'Dependencies/build/macos15/StandalonePython'
if not (python_target/'python/lib/libpython3.11.dylib').exists():
 python_target.mkdir(parents=True,exist_ok=True)
 with tarfile.open(python_archive) as tar:tar.extractall(python_target,filter='data')
xz=lab/'xz-5.8.4.tar.gz';xzurl='https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz'
if not xz.exists():urllib.request.urlretrieve(xzurl,xz)
assert hashlib.sha256(xz.read_bytes()).hexdigest()=='0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9'
src=lab/'xz-5.8.4'
if not src.exists():
 with tarfile.open(xz) as tar:tar.extractall(lab,filter='data')
output=root/'Dependencies/build/macos15';output.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,MACOSX_DEPLOYMENT_TARGET='15.0',CFLAGS='-O2 -mmacosx-version-min=15.0',LDFLAGS='-mmacosx-version-min=15.0')
with (lab/'xz-build.log').open('w') as log:
 subprocess.run([str(src/'configure'),'--disable-static','--enable-shared','--disable-xz','--disable-xzdec','--disable-lzmadec','--disable-lzmainfo','--disable-scripts','--disable-doc'],cwd=src,env=env,stdout=log,stderr=log,check=True)
 subprocess.run(['make','-j4'],cwd=src,env=env,stdout=log,stderr=log,check=True)
library=src/'src/liblzma/.libs/liblzma.5.dylib'
shutil.copy2(library,output/'liblzma.5.dylib')
provenance={'mlxVersion':'0.32.2','wheel':wheel['filename'],'wheelURL':wheel['url'],'wheelSHA256':wheel['digests']['sha256'],'xzVersion':'5.8.4','xzURL':xzurl,'xzSHA256':hashlib.sha256(xz.read_bytes()).hexdigest(),'deploymentTarget':'15.0','modelPackage':'assets/catalogs/index-mlx-package.json','additionalModelDownloadBytes':0}
provenance.update(mlxCoreWheel=core['filename'],mlxCoreSHA256=core['digests']['sha256'],pythonVersion='3.11.17',pythonArchive=python['name'],pythonURL=python['browser_download_url'],pythonSHA256=python['digest'].removeprefix('sha256:'))
(output/'runtime-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
print('Compatible MLX and liblzma prepared; no model download')
