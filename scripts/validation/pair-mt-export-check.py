import json,time,torch
from pathlib import Path
from transformers import MarianMTModel,MarianTokenizer
root=Path('docs/benchmarks/pair-mt-ru-en');rows=json.loads((root/'corpus.json').read_text());out=[]
torch.set_num_threads(4)
for lang in ['ru','en']:
 path=Path('.build/pair-mt')/('ru-en' if lang=='ru' else 'en-ru')/'original'
 tok=MarianTokenizer.from_pretrained(path,local_files_only=True);model=MarianMTModel.from_pretrained(path,local_files_only=True).eval()
 for r in rows:
  if r['id'] not in [lang+'-time',lang+'-payment',lang+'-route' if lang=='ru' else lang+'-register']:continue
  with torch.inference_mode():
   t=time.monotonic();result=model.generate(**tok(r['text'],return_tensors='pt'),num_beams=4,max_new_tokens=512,do_sample=False)
  item={'id':r['id'],'text':tok.decode(result[0],skip_special_tokens=True),'seconds':time.monotonic()-t};out.append(item);print(item,flush=True)
 del model
(root/'pytorch-export-check.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
