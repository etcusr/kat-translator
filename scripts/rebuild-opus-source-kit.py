#!/usr/bin/env python3
from pathlib import Path
import tarfile,json,hashlib,subprocess,shutil
import argparse
parser=argparse.ArgumentParser(description='Clean Opus SDK rebuild from the hash-locked source kit; no network or vendor-tree mutation')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--sign-identity', help='Optional Apple Development/Distribution identity for the newly built SDK package')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1];w=args.output.resolve();w.mkdir(parents=True,exist_ok=False);src=w/'sources';src.mkdir()
kit=root/'dist/licensing/dependency-sources-2026-10-14';lock={e['file']:e for e in json.loads((root/'docs/licensing/2026-10-14/dependency-sources.json').read_text())['archives']}
used=[]
def extract(name,dest):
 if Path(name).name != name or not dest.resolve().is_relative_to(src):
  raise ValueError('Unsafe source archive or destination')
 p=kit/name;e=lock[name]
 if p.is_symlink() or p.stat().st_size != e['bytes'] or hashlib.file_digest(p.open('rb'),'sha256').hexdigest()!=e['sha256']:
  raise ValueError('Source archive mismatch: '+name)
 dest.mkdir(parents=True,exist_ok=True)
 with tarfile.open(p) as t:
  for m in t.getmembers():
   parts=Path(m.name).parts
   if len(parts)<2:continue
   m.name=str(Path(*parts[1:]))
   t.extract(m,dest,filter='data')
 used.append(dict(archive=name,sha256=e['sha256'],destination=str(dest.relative_to(src))))
ct=src/'CTranslate2';sp=src/'sentencepiece'
extract('CTranslate2.tar.gz',ct);extract('sentencepiece.tar.gz',sp)
parents={'OpenNMT/CTranslate2':ct}
for e in json.loads((root/'docs/licensing/2026-10-14/source-submodules.json').read_text()):
 if e['parent']=='OpenNMT/CTranslate2' and e['path'] not in ['third_party/spdlog','third_party/ruy']:continue
 if e['parent'] in parents:
  dest=parents[e['parent']]/e['path'];extract(e['archive'],dest);parents[e['repository']]=dest
patch=root/'shared/native/OpusRuntime/mobile-cancel.patch'
patch_lock=next(e for e in json.loads((root/'docs/licensing/2026-10-14/source-patches.json').read_text()) if e['component']=='CTranslate2')
if hashlib.file_digest(patch.open('rb'),'sha256').hexdigest()!=patch_lock['sha256']:
 raise ValueError('CTranslate2 patch differs from source-kit lock')
subprocess.run(['patch','-p1','--batch','--forward','-i',str(patch)],cwd=ct,check=True)
subprocess.run(['patch','-p1','--batch','--reverse','--dry-run','-i',str(patch)],cwd=ct,check=True)
commands=[]
def run(cmd):
 commands.append(cmd);subprocess.run(cmd,check=True)
frames=[]
for sdk,flavor,target in [('iphoneos','ios','18.0'),('iphonesimulator','simulator','18.0'),('macosx','macos','15.0')]:
 build=w/'opus'/flavor
 sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
 cmd=['cmake','-S',str(root/'shared/native/OpusRuntime'),'-B',str(build),'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_POLICY_VERSION_MINIMUM=3.5',f'-DCMAKE_OSX_SYSROOT={sdkpath}','-DCMAKE_OSX_ARCHITECTURES=arm64',f'-DCMAKE_OSX_DEPLOYMENT_TARGET={target}',f'-DCT2_SOURCE={ct}',f'-DSPM_SOURCE={sp}']
 if sdk!='macosx':cmd.append('-DCMAKE_SYSTEM_NAME=iOS')
 run(cmd);run(['cmake','--build',str(build),'--target','OpusRuntime','-j4'])
 frame=build/'OpusRuntime.framework';content=frame/'Versions/A' if sdk=='macosx' else frame
 (content/'Headers').mkdir(exist_ok=True);(content/'Modules').mkdir(exist_ok=True)
 shutil.copy2(root/'shared/native/OpusRuntime/OpusRuntime.h',content/'Headers/OpusRuntime.h')
 (content/'Modules/module.modulemap').write_text('framework module OpusRuntime { umbrella header "OpusRuntime.h" export * }\n')
 privacy=root/('Dependencies/privacy/macos/NoCollection.xcprivacy' if sdk=='macosx' else 'Dependencies/privacy/ios/OpusRuntime.xcprivacy')
 resource=content/'Resources' if sdk=='macosx' else content
 resource.mkdir(exist_ok=True)
 shutil.copy2(privacy,resource/'PrivacyInfo.xcprivacy')
 if sdk=='macosx':
  for name in ['Headers','Modules']:
   if not (frame/name).exists():(frame/name).symlink_to('Versions/Current/'+name)
 run(['install_name_tool','-id','@rpath/OpusRuntime.framework/OpusRuntime',str(frame/'OpusRuntime')]);frames.append(frame)
output=w/'OpusRuntime.xcframework';run(['xcodebuild','-create-xcframework']+sum([['-framework',str(f)] for f in frames],[])+['-output',str(output)])
# Public paths are relative; toolchain versions are captured separately.
(w/'opus-build-inputs.json').write_text(json.dumps(dict(inputs=used,patchSHA256=hashlib.file_digest(patch.open('rb'),'sha256').hexdigest(),commands=[[a.replace(str(root),'$ROOT') for a in cmd] for cmd in commands]),indent=2)+'\n')
if args.sign_identity:
 run(['codesign','--force','--timestamp','--sign',args.sign_identity,str(output)])
 run(['codesign','--verify','--deep','--strict',str(output)])
print('Clean source-kit Opus rebuild complete')
