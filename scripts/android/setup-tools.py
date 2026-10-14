#!/usr/bin/env python3
"""Install pinned Android tools inside .build; leaves Apple/global toolchains alone.

The SDK manager displays Google's SDK license before installation. Run interactively.
"""
import hashlib,json,os,platform,subprocess,tarfile,urllib.request,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.build/android-tools'
def download(url,name,sha):
    path=BASE/'downloads'/name;path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists():
        temporary=path.with_suffix(path.suffix+'.partial')
        urllib.request.urlretrieve(url,temporary);temporary.replace(path)
    with path.open('rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=sha:raise RuntimeError('Digest mismatch: '+str(path))
    return path

def unzip(path,dest):
    with zipfile.ZipFile(path) as z:
        for entry in z.infolist():
            target=(dest/entry.filename).resolve()
            if not target.is_relative_to(dest.resolve()):raise ValueError('Unsafe ZIP entry')
        z.extractall(dest)
        for entry in z.infolist():
            mode=entry.external_attr>>16
            if mode:(dest/entry.filename).chmod(mode & 0o777)

if __name__=='__main__':
    if platform.system()!='Darwin' or platform.machine()!='arm64':raise SystemExit('This bootstrap is for the current Apple Silicon host; use equivalent JDK17/SDK packages on other hosts.')
    jdk=download('https://cdn.azul.com/zulu/bin/zulu17.68.203-ca-jdk17.0.20.1-macosx_aarch64.tar.gz','zulu.tar.gz','ed54397260c5994b2fc4e31c780f480b947e6532bc6a5ac7754355d5dd4c127d')
    if not (BASE/'java-home').exists():
        with tarfile.open(jdk) as t:t.extractall(BASE,filter='data')
        (BASE/'java-home').symlink_to('zulu17.68.203-ca-jdk17.0.20.1-macosx_aarch64/Contents/Home',target_is_directory=True)
    sdk=BASE/'sdk';cli=sdk/'cmdline-tools'
    archive=download('https://dl.google.com/android/repository/commandlinetools-mac_arm64-15859902_latest.zip','commandline.zip','835b62a26162b229b441d1f6d4680383815a270809eb33522c0d480fa5002c4e')
    if not (cli/'latest').exists():
        cli.mkdir(parents=True,exist_ok=True);unzip(archive,cli);(cli/'cmdline-tools').rename(cli/'latest')
    env=os.environ|{'JAVA_HOME':str(BASE/'java-home'),'ANDROID_HOME':str(sdk),'ANDROID_USER_HOME':str(BASE/'user-home')}
    (BASE/'user-home').mkdir(exist_ok=True)
    subprocess.run([str(cli/'latest/bin/sdkmanager'),'--sdk_root='+str(sdk),'platform-tools','platforms;android-36','build-tools;36.0.0','ndk;28.2.13676358','cmake;3.22.1'],env=env,check=True)
    ndk=sdk/'ndk/28.2.13676358';nested=ndk/'android-ndk-r28c'
    # Some SDK package layouts retain the archive's top-level directory.
    if nested.is_dir() and not (ndk/'source.properties').exists():
        for entry in nested.iterdir():
            if entry.name=='.DS_Store':continue
            if (ndk/entry.name).exists():raise RuntimeError('NDK destination already exists: '+entry.name)
            entry.rename(ndk/entry.name)
    print('Tools ready. Run scripts/android/build.sh')
