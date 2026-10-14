import ctypes as c, json, time
from pathlib import Path
root=Path.cwd()
lib=c.CDLL(str(root/'Dependencies/build/translation/macosx/TranslationRuntime.framework/TranslationRuntime'))
lib.ot_mt_load.argtypes=[c.c_char_p];lib.ot_mt_load.restype=c.c_void_p
lib.ot_mt_free.argtypes=[c.c_void_p]
lib.ot_mt_flag_create.restype=c.c_void_p
lib.ot_mt_flag_free.argtypes=[c.c_void_p]
lib.ot_mt_count.argtypes=[c.c_void_p,c.c_char_p,c.c_char_p,c.c_char_p];lib.ot_mt_count.restype=c.c_int
lib.ot_mt_run.argtypes=[c.c_void_p,c.c_char_p,c.c_char_p,c.c_char_p,c.c_void_p,c.c_char_p,c.c_size_t,c.POINTER(c.c_double)];lib.ot_mt_run.restype=c.c_int
start=time.monotonic();handle=lib.ot_mt_load(str(root/'model-store/downloads/translategemma-4b-it.Q4_K_M.gguf').encode());assert handle,'load failed'
print('load',time.monotonic()-start,flush=True)
fixtures=[('ru','en','Не добавляйте сахар.'),('ru','en','Это не мой чемодан. Поезд отправляется в 17:45.'),('ru','en','Не отменяйте весь заказ.'),('en','ru','Do not add sugar.'),('en','ru','This is not my suitcase. The train leaves at 17:45.'),('en','ru','Do not cancel the whole order.')]
for src,dst,text in fixtures:
 s={'ru':'Russian','en':'English'}[src];t={'ru':'Russian','en':'English'}[dst]
 prefix=f'<bos><start_of_turn>user\nYou are a professional {s} ({src}) to {t} ({dst}) translator. Your goal is to accurately convey the meaning and nuances of the original {s} text while adhering to {t} grammar, vocabulary, and cultural sensitivities.\nProduce only the {t} translation, without any additional explanations or commentary. Please translate the following {s} text into {t}:\n\n\n'.encode()
 suffix=b'<end_of_turn>\n<start_of_turn>model\n';out=c.create_string_buffer(65536);first=c.c_double();flag=lib.ot_mt_flag_create();start=time.monotonic()
 code=lib.ot_mt_run(handle,prefix,text.encode(),suffix,flag,out,len(out),c.byref(first));lib.ot_mt_flag_free(flag)
 print(json.dumps({'source':text,'translation':out.value.decode(),'code':code,'seconds':time.monotonic()-start,'first':first.value,'tokens':lib.ot_mt_count(handle,prefix,text.encode(),suffix)},ensure_ascii=False),flush=True)
 assert code==0
lib.ot_mt_free(handle)
