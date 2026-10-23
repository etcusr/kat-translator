#!/usr/bin/env python3
"""Build pinned Store-only CPython without unused TLS extensions; no model downloads."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tarfile
import urllib.request
ROOT=Path(__file__).resolve().parents[1]
VERSION='3.11.17'
URL=f'https://www.python.org/ftp/python/{VERSION}/Python-{VERSION}.tar.xz'
SHA256='bfb74ad39efae27cda510f134ab408e00f9992c56851cfc0b1cdb5646da11599'
WORK=ROOT/'.build/macos-store-python'
PREFIX=ROOT/'Dependencies/build/macos-store-python/3.11.17-no-tls-v1/python'
DISABLED=('_ssl','_hashlib','_tkinter')

def validate():
    python=PREFIX/'bin/python3.11'
    code=f'''import importlib.util, hashlib, ctypes, zlib, bz2, sqlite3, json, multiprocessing, sys
assert sys.version_info[:3] == (3,11,17)
assert importlib.util.find_spec('_ssl') is None
assert importlib.util.find_spec('_hashlib') is None
assert hashlib.sha256(b'kat').hexdigest() == '{hashlib.sha256(b"kat").hexdigest()}'
'''
    subprocess.run([str(python),'-I','-c',code],check=True)
    for path in [python,PREFIX/'lib/libpython3.11.dylib']:
        data=path.read_bytes()
        if any(token in data for token in (b'OpenSSL 3.',b'OPENSSL_init_crypto',b'PyInit__ssl',b'PyInit__hashlib')):
            raise RuntimeError('Unexpected built-in TLS implementation: '+str(path))

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    receipt=PREFIX.parent/'provenance.json'
    if receipt.exists():
        x=json.loads(receipt.read_text())
        if x['sourceSHA256']!=SHA256 or x['disabledModules']!=list(DISABLED):raise RuntimeError('Runtime provenance mismatch')
        validate();print('Verified existing Store Python');return
    archive=WORK/f'Python-{VERSION}.tar.xz'
    if not archive.exists():
        part=archive.with_suffix('.download')
        urllib.request.urlretrieve(URL,part)
        if hashlib.sha256(part.read_bytes()).hexdigest()!=SHA256:raise RuntimeError('CPython download checksum mismatch')
        part.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256:raise RuntimeError('CPython source checksum mismatch')
    source=WORK/f'Python-{VERSION}'
    if not source.exists():
        with tarfile.open(archive) as tar:tar.extractall(WORK,filter='data')
    (source/'Modules/Setup.local').write_text('*disabled*\n'+'\n'.join(DISABLED)+'\n')
    sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    env={**os.environ,'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','SDKROOT':sdk,
         'MACOSX_DEPLOYMENT_TARGET':'15.0','CFLAGS':'-O2 -mmacosx-version-min=15.0',
         'LDFLAGS':'-mmacosx-version-min=15.0','ac_cv_working_openssl_ssl':'no',
         'ac_cv_working_openssl_hashlib':'no'}
    commands=[['./configure','--prefix='+str(PREFIX),'--enable-shared','--without-static-libpython',
               '--with-ensurepip=no','--disable-test-modules','--with-pkg-config=no'],
              ['make','-j4'],['make','install','COMPILEALL_OPTS=-j2']]
    for index,command in enumerate(commands):
        with (WORK/f'{index}-build.log').open('w') as log:
            subprocess.run(command,cwd=source,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    validate()
    receipt.write_text(json.dumps(dict(pythonVersion=VERSION,sourceURL=URL,sourceSHA256=SHA256,
        disabledModules=list(DISABLED),deploymentTarget='15.0',configure=commands[0][2:],
        compiler=subprocess.check_output(['xcrun','clang','--version'],text=True).splitlines()[0]),indent=2)+'\n')
    print('Built and verified Store-only Python without SSL/hashlib extensions')
if __name__=='__main__':main()
