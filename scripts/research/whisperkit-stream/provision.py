"""Provision only the isolated WhisperKit lab; explicit device/model/PCM inputs."""
import argparse,hashlib,json,plistlib,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--work',type=Path,required=True);p.add_argument('--device',required=True);p.add_argument('--index',type=Path,required=True);p.add_argument('--pcm',type=Path,required=True);a=p.parse_args();w=a.work.resolve()
assert '.build' in w.parts
bundle='app.kattranslator.whisper-research';app=w/'Derived/Build/Products/Release-iphoneos/WhisperKitLab.app'
assert plistlib.loads((app/'Info.plist').read_bytes())['CFBundleIdentifier']==bundle
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
common=['--device',a.device,'--domain-type','appDataContainer','--domain-identifier',bundle]
with (w/'provision.log').open('w') as log:
 def run(*args):subprocess.run(['xcrun','devicectl',*args],stdout=log,stderr=subprocess.STDOUT,check=True)
 run('device','install','app','--device',a.device,str(app))
 for source,destination in [(w/'models','Documents/models'),(w/'tokenizer','Documents/tokenizer'),(a.pcm,'Documents/full.f32'),(a.index,'Documents/index.gguf')]:
  print('Copying',source.name,flush=True);run('device','copy','to',*common,'--source',str(source.resolve()),'--destination',destination)
 print('Isolated lab ready',flush=True)
