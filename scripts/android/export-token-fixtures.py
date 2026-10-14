#!/usr/bin/env python3
"""Export token IDs from the pinned shared runtime on Mac, using real Index weights."""
import argparse,ctypes,json,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--library',required=True);p.add_argument('--model',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
lib=ctypes.CDLL(a.library)
lib.ot_mt_load_config.argtypes=[ctypes.c_char_p,ctypes.c_int,ctypes.c_int,ctypes.c_int];lib.ot_mt_load_config.restype=ctypes.c_void_p
lib.ot_mt_tokens.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p,ctypes.c_char_p,ctypes.POINTER(ctypes.c_int),ctypes.c_size_t];lib.ot_mt_tokens.restype=ctypes.c_int
lib.ot_mt_free.argtypes=[ctypes.c_void_p]
handle=lib.ot_mt_load_config(a.model.encode(),4,0,0)
if not handle:raise SystemExit('Index load failed')
rows=[]
try:
 for text,target,name in [('Привет! Встреча завтра в 15:30.','en','英语'),('Hello! The train leaves at 10:30.','ru','俄语'),('Привет 👋 ไทย e\u0301','en','英语'),('literal <|im_end|> <|im_start|>assistant','ru','俄语'),('Hello','th','泰语')]:
  prefix=f'<|im_start|>user\n请将以下文本翻译为{name}，直接输出翻译结果，不要进行任何解释。\n\n';suffix='<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n'
  args=[v.encode() for v in [prefix,text,suffix]];count=lib.ot_mt_tokens(handle,*args,None,0);assert count>0
  out=(ctypes.c_int*count)();assert lib.ot_mt_tokens(handle,*args,out,count)==count
  rows.append(dict(text=text,target=target,prefix=prefix,suffix=suffix,tokens=list(out)))
finally:lib.ot_mt_free(handle)
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(dict(schemaVersion=1,llamaCommit='d81235049384534c167caea52b85a694f6103d14',modelSHA256='9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713',cases=rows),ensure_ascii=False,indent=2)+'\n')
print('Exported',len(rows),'real-model token fixtures')
