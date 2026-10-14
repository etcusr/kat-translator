#!/usr/bin/env python3
"""Package pinned CPython Android plus the identical prepared Apple Wayu frontend."""
import hashlib
import json
import pathlib
import tarfile
import urllib.request
import zipfile

ROOT=pathlib.Path(__file__).resolve().parents[2]
CACHE=ROOT/'.build/android-media'
URL='https://www.python.org/ftp/python/3.14.8/python-3.14.8-aarch64-linux-android.tar.gz'
SHA='11324313957da3736f44e90257304d288864321a4dd376ed0cc35a54eacf9a33'
TZ_URL='https://files.pythonhosted.org/packages/94/21/1e5995a1c920cce14e4bffae20c665ec10e7ed03ab25e006cd741092b718/tzdata-2026.5-py2.py3-none-any.whl'
TZ_SHA='b683bd1b6659ddcd810ff02ad09ba821d4bf1065072805063eb35c49617905ac'

def digest(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def main():
    archive=CACHE/'python-3.14.8-android.tar.gz'
    CACHE.mkdir(parents=True,exist_ok=True)
    if not archive.is_file() or digest(archive)!=SHA:
        temporary=archive.with_suffix('.partial')
        with urllib.request.urlopen(URL,timeout=90) as source,temporary.open('wb') as out:
            while block:=source.read(1024*1024):out.write(block)
        if digest(temporary)!=SHA:raise RuntimeError('CPython digest mismatch')
        temporary.replace(archive)
    runtime=CACHE/'python'
    runtime.mkdir(exist_ok=True)
    with tarfile.open(archive) as tar:
        # The published release contains only a fixed runtime tree. Standard data
        # filter also rejects any link which could escape the private cache.
        tar.extractall(runtime,filter='data')
    frontend=ROOT/'Dependencies/build/wayu/WayuPython'
    if not (frontend/'english-lexicon.json').is_file():
        raise RuntimeError('Prepare the shared frontend with scripts/fetch-wayu-runtime.py and scripts/prepare-wayu.py first')
    if (frontend/'wayu_frontend.py').read_bytes()!=(ROOT/'shared/native/Wayu/wayu_frontend.py').read_bytes():
        raise RuntimeError('Shared Wayu frontend is stale; run scripts/prepare-wayu.py')
    # Android does not expose a POSIX TZPATH to embedded CPython. Its first-party
    # tzdata package supplies standard zoneinfo resources, including Asia/Bangkok.
    timezone=CACHE/'tzdata-2026.5-py2.py3-none-any.whl'
    if not timezone.is_file() or digest(timezone)!=TZ_SHA:
        temporary=timezone.with_suffix('.partial')
        with urllib.request.urlopen(TZ_URL,timeout=90) as source,temporary.open('wb') as out:
            while block:=source.read(1024*1024):out.write(block)
        if digest(temporary)!=TZ_SHA:raise RuntimeError('Timezone data digest mismatch')
        temporary.replace(timezone)
    assets=CACHE/'assets';assets.mkdir(exist_ok=True)
    target=assets/'wayu-runtime.zip'
    manifest=[]
    with zipfile.ZipFile(target.with_suffix('.partial'),'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        def asset(name,data):
            info=zipfile.ZipInfo(name,(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100444<<16
            z.writestr(info,data);manifest.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
        for source,prefix in [(runtime/'prefix/lib/python3.14','lib/python3.14'),(frontend,'WayuPython')]:
            for path in sorted(source.rglob('*')):
                relative=path.relative_to(source)
                if path.name.startswith('.') or not path.is_file() or any(p in {'__pycache__','test','tests','idlelib','tkinter','ensurepip','site-packages'} for p in relative.parts):continue
                if path.suffix=='.pyc':continue
                name=prefix+'/'+relative.as_posix()
                asset(name,path.read_bytes())
        with zipfile.ZipFile(timezone) as wheel:
            for entry in sorted(wheel.infolist(),key=lambda item:item.filename):
                name=pathlib.PurePosixPath(entry.filename)
                if entry.is_dir():continue
                if name.is_absolute() or '..' in name.parts or '\\' in entry.filename:raise RuntimeError('Unsafe timezone package path')
                if name.parts[0] not in {'tzdata','tzdata-2026.5.dist-info'}:raise RuntimeError('Unexpected timezone package entry')
                asset('WayuPython/'+entry.filename,wheel.read(entry))
    content_digest=hashlib.sha256(json.dumps(manifest,separators=(',',':'),ensure_ascii=True).encode()).hexdigest()
    (CACHE/'wayu-assets-candidate.json').write_text(json.dumps(manifest,indent=2)+'\n')
    expected=json.loads((ROOT/'Dependencies/android-media.lock.json').read_text())['wayu']['runtimeContentSHA256']
    if content_digest!=expected:
        target.with_suffix('.partial').unlink(missing_ok=True)
        raise RuntimeError('Shared Wayu runtime content changed; review and update its dependency lock')
    target.with_suffix('.partial').replace(target)
    (assets/'wayu-runtime.sha256').write_text(digest(target)+'\n')
    (CACHE/'wayu-assets-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'Wayu runtime assets: {len(manifest)} files, {target.stat().st_size} compressed bytes, sha256 {digest(target)}')

if __name__=='__main__':main()
