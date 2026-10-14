#!/usr/bin/env python3
"""Export the existing OPUS Big checkpoint to research-only FP16 GGUF; no retraining."""
from pathlib import Path
import importlib.util,sys,hashlib,json,os
root=Path(__file__).resolve().parents[3]
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1')
sys.path.insert(0,str(root/'Dependencies/vendor/llama.cpp/gguf-py'))
spec=importlib.util.spec_from_file_location('upstream',root/'.build/opus-vulkan-lab/vendor/sussurro/scripts/convert.py')
up=importlib.util.module_from_spec(spec);spec.loader.exec_module(up)
import torch,numpy as np
from transformers import MarianMTModel,MarianTokenizer
from gguf import GGUFWriter
for direction in sys.argv[1:] or ['zle-en']:
 source=root/'.build/opus-gpu-release/weights'/direction
 out=root/'model-store/research/opus-vulkan'/f'{direction}-f16.gguf'
 model=MarianMTModel.from_pretrained(source,local_files_only=True).eval()
 tokenizer=MarianTokenizer.from_pretrained(source,local_files_only=True)
 writer=GGUFWriter(str(out),up.ARCH);up.add_metadata(writer,model.config,tokenizer,source)
 for name,tensor in model.state_dict().items():
  if name in ['model.encoder.embed_tokens.weight','model.decoder.embed_tokens.weight','lm_head.weight','model.encoder.embed_positions.weight','model.decoder.embed_positions.weight']:continue
  array=np.ascontiguousarray(tensor.detach().float().numpy())
  if array.ndim>=2 and min(array.shape)>1:array=array.astype(np.float16)
  writer.add_tensor(name,array)
 writer.write_header_to_file();writer.write_kv_data_to_file();writer.write_tensors_to_file();writer.close()
 def digest(p):
  h=hashlib.sha256()
  with p.open('rb') as f:
   for block in iter(lambda:f.read(1048576),b''):h.update(block)
  return h.hexdigest()
 manifest={'source':str(source.resolve()),'source_sha256':digest(source/'model.safetensors'),'output':str(out.relative_to(root)),'bytes':out.stat().st_size,'sha256':digest(out),'precision':'FP16 weights; F32 vectors','model':'OPUS-MT TC Big '+direction,'experimental':True}
 out.with_suffix('.json').write_text(json.dumps(manifest,indent=2)+'\n');print(manifest)
