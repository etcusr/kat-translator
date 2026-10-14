#!/usr/bin/env python3
"""Preflight shared model fixtures, then import as the app UID via instrumentation.

No device command is run unless --install is explicit. Never copies Index.
Usage: source scripts/android/env.sh
 python3 scripts/android/install-media-fixtures.py --ids wayu-prosody --install
Root owns device exclusivity/thermal scheduling. This script only stages/imports;
it does not run inference, start downloads, alter preferences, or install APKs.
"""
import argparse
import hashlib
import json
import os
import pathlib
import shlex
import subprocess
import sys

ROOT=pathlib.Path(__file__).resolve().parents[2]
APP='org.openoffline.translator.android'
DEFAULT_IDS=['whisper-large-v3-turbo-f16','vits-piper-en_US-lessac-medium',
 'sherpa-onnx-supertonic-3-tts-int8-2026-05-11','ppocr-v5-english','ppocr-v5-det',
 'wayu-prosody','omnivoice-q8-base']

def load(name):return json.loads((ROOT/'assets/catalogs'/name).read_text())
def digest(path):
    with path.open('rb') as source:return hashlib.file_digest(source,'sha256').hexdigest()

def inventory(overrides):
    packages={}
    manifests={p['id']:p for p in load('voice-manifests.json')}
    models=load('models.json')['models']+load('android-ocr.json')['models']
    singles={'whisper-large-v3-turbo-f16':'whisper-large-v3-turbo-f16.bin','ppocr-v5-english':'ocr-english.onnx','ppocr-v5-eslav':'ocr-eslav.onnx','ppocr-v5-det':'ocr-det.onnx'}
    for item in models:
        identity=item['id']
        if identity in singles:
            source=overrides.get(identity,ROOT/'model-store/downloads'/singles[identity])
            packages[identity]=[(source,'model.bin',item['byteCount'],item['sha256'])]
        elif identity in manifests:
            directory=overrides.get(identity,ROOT/'.build/verified-voices'/identity)
            packages[identity]=[(directory/f['path'],f['path'],f['byteCount'],f['sha256']) for f in manifests[identity]['files']]
    wayu=load('android-capabilities.json')['wayu']
    wayu_names={'wayu-prosody.bin':'prosody_fp32.onnx','wayu-curves.bin':'curves_fp32.onnx','wayu-decoder.bin':'decoder_fp32.onnx','wayu-styles.bin':'voicepacks.npz'}
    directory=overrides.get('wayu-prosody',ROOT/'model-store/downloads/wayu')
    packages['wayu-prosody']=[(directory/wayu_names[f['path']],f['path'],f['byteCount'],f['sha256']) for f in wayu]
    omni=manifests['omnivoice-q8-base'];directory=overrides.get(omni['id'],ROOT/'model-store/downloads/omnivoice')
    packages[omni['id']]=[(directory/f['path'],f['path'],f['byteCount'],f['sha256']) for f in omni['files']]
    return packages

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ids',nargs='+',default=DEFAULT_IDS)
    parser.add_argument('--source',action='append',default=[],metavar='ID=PATH',help='Override host file/directory (Wayu uses original shared download filenames)')
    parser.add_argument('--serial',default=os.environ.get('ANDROID_SERIAL'))
    parser.add_argument('--fixture-root',default='/data/local/tmp/kat-media-fixtures')
    parser.add_argument('--install',action='store_true',help='Stage with adb, then app-context instrumentation atomically imports')
    parser.add_argument('--out',type=pathlib.Path,default=ROOT/'.build/android-media/fixture-import')
    args=parser.parse_args()
    if not args.fixture_root.startswith('/data/local/tmp/') or '..' in pathlib.PurePosixPath(args.fixture_root).parts:
        parser.error('fixture-root must be a scoped directory below /data/local/tmp')
    overrides={}
    for value in args.source:
        identity,separator,path=value.partition('=')
        if not separator:parser.error('--source requires ID=PATH')
        overrides[identity]=pathlib.Path(path).expanduser().resolve()
    packages=inventory(overrides);plan=[]
    for identity in args.ids:
        if identity=='index-translate-9b-q4km':parser.error('Index is intentionally excluded: use its already installed shared model')
        if identity not in packages:parser.error(f'Unknown supported fixture package: {identity}')
        entries=packages[identity]
        for source,relative,size,sha in entries:
            if not source.is_file():raise RuntimeError(f'Missing shared file {source}; provide --source {identity}=PATH')
            if source.stat().st_size!=size or digest(source)!=sha:raise RuntimeError(f'Shared catalog digest/size mismatch: {source}')
            if relative.startswith('/') or '..' in pathlib.PurePosixPath(relative).parts:raise RuntimeError('Unsafe catalog path')
        destination=identity+'.bin' if len(entries)==1 and entries[0][1]=='model.bin' else identity
        plan.append({'id':identity,'files':len(entries),'bytes':sum(f[2] for f in entries),'destination':f'context.getExternalFilesDir(null)/packages/{destination}'})
    print(json.dumps({'verified':plan,'deviceActions':args.install},indent=2),flush=True)
    if not args.install:return
    adb=['adb']+(['-s',args.serial] if args.serial else [])
    args.out.mkdir(parents=True,exist_ok=True)
    # Start instrumentation in a stopped application, so its package lock has one owner.
    subprocess.run(adb+['shell','am','force-stop',APP],check=True)
    for item in plan:
        identity=item['id'];stage=args.fixture_root+'/'+identity
        # Shell owns only /data/local/tmp staging. It must never mkdir app storage.
        parents={str(pathlib.PurePosixPath(stage)/relative).rsplit('/',1)[0] for _,relative,_,_ in packages[identity]}
        subprocess.run(adb+['shell','mkdir -p '+' '.join(shlex.quote(p) for p in sorted(parents))],check=True)
        for source,relative,_,_ in packages[identity]:
            subprocess.run(adb+['push',str(source),stage+'/'+relative],check=True,stdout=subprocess.DEVNULL)
        command=adb+['shell','am','instrument','-w','-e','class',APP+'.AppOwnedPackageFixtureTest#importExactSharedPackage',
                     '-e','packageId',identity,'-e','fixtureRoot',args.fixture_root,APP+'.test/androidx.test.runner.AndroidJUnitRunner']
        result=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        (args.out/(identity+'.log')).write_text(result.stdout)
        print(result.stdout,flush=True)
        if result.returncode or 'OK (1 test)' not in result.stdout or 'FAILURES!!!' in result.stdout:
            raise RuntimeError(f'App-owned import failed for {identity}; staging retained for diagnosis')
        subprocess.run(adb+['shell','rm -rf '+shlex.quote(stage)],check=True)
    print('Shared packages imported by app context; no inference was run.')

if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError,subprocess.CalledProcessError) as error:
        print(str(error),file=sys.stderr);sys.exit(1)
