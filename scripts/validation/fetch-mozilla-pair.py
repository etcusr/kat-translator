import json,urllib.request,gzip,hashlib
from pathlib import Path
root=Path('.build/pair-mt');data=json.loads((root/'mozilla-registry.json').read_text());out={}
for direction in ['ru-en','en-ru']:
 model=data['models'][direction][0];dest=root/'mozilla'/direction;dest.mkdir(parents=True,exist_ok=True);out[direction]=dict(model=model,files={})
 for key,info in model['files'].items():
  url=data['baseUrl']+'/'+info['path'];archive=dest/(key+'.gz');target=dest/key
  urllib.request.urlretrieve(url,archive);raw=gzip.decompress(archive.read_bytes());digest=hashlib.sha256(raw).hexdigest()
  if 'uncompressedHash' in info:assert digest==info['uncompressedHash']
  target.write_bytes(raw);out[direction]['files'][key]=dict(url=url,compressedBytes=archive.stat().st_size,bytes=len(raw),sha256=digest)
  print(direction,key,len(raw),flush=True)
Path('docs/benchmarks/pair-mt-ru-en/mozilla-model-manifest.json').write_text(json.dumps(out,indent=2)+'\n')
