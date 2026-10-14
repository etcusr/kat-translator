"""Exercise the production C runtime and compare its host math with upstream."""
import ctypes as C, pathlib, sys, json, time, wave, importlib.util
import numpy as np
root=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'Dependencies/build/wayu/WayuPython'))
import wayu_frontend as front
lib=C.CDLL(str(root/'.build/wayu-probe/libwayu.dylib'))
lib.ot_wayu_load.argtypes=[C.c_char_p]*3;lib.ot_wayu_load.restype=C.c_void_p
lib.ot_wayu_generate.argtypes=[C.c_void_p,C.POINTER(C.c_int64),C.c_int,C.POINTER(C.c_float),C.POINTER(C.c_int),C.c_void_p];lib.ot_wayu_generate.restype=C.POINTER(C.c_float)
lib.ot_wayu_audio_free.argtypes=[C.POINTER(C.c_float)];lib.ot_wayu_free.argtypes=[C.c_void_p]
lib.ot_wayu_harmonic.argtypes=[C.POINTER(C.c_float),C.c_int,C.c_int];lib.ot_wayu_harmonic.restype=C.POINTER(C.c_float)
models=root/'model-store/downloads/wayu'
spec=importlib.util.spec_from_file_location('wayu_reference',root/'.build/wayu-source/onnx_infer.py');ref=importlib.util.module_from_spec(spec);sys.modules[spec.name]=ref;spec.loader.exec_module(ref)
source=np.load(models/'source_params.npz')
# Independent source excitation without stochastic noise; same interpolation, DFT.
f0=np.array([0,120,155,200,95,0],dtype=np.float32)
x=np.repeat(f0.astype(np.float64),300)[None,:,None]
rad=x*np.arange(1,10)/24000;rad-=np.floor(rad)
phase=ref._resample(np.cumsum(ref._resample(rad,1/300),axis=1)*2*np.pi*300,300)
merged=np.tanh((np.sin(phase)*0.1*(x>10))@source['weight'].T+source['bias'])
expected=ref._stft(merged[0,:,0].astype(np.float32),source['window'])
p=lib.ot_wayu_harmonic(f0.ctypes.data_as(C.POINTER(C.c_float)),len(f0),0);assert p
actual=np.ctypeslib.as_array(p,shape=(expected.size,)).copy().reshape(expected.shape);lib.ot_wayu_audio_free(p)
# Phase is undefined for zero-amplitude bins; compare reconstructed complex spectra.
def spectrum(a):return a[:,:11]*np.exp(1j*a[:,11:])
error=float(np.max(np.abs(spectrum(actual)-spectrum(expected))));assert error<2e-5,error
print('Harmonic source parity max complex error',error,flush=True)
h=lib.ot_wayu_load(*[str(models/f'{s}_fp32.onnx').encode() for s in ['prosody','curves','decoder']]);assert h
cases=['สวัสดีค่ะ สบายดีไหมคะ?','สวัสดีครับ สบายดีไหมครับ','ราคา 250 บาท','ผมแพ้ถั่วลิสง อาหารจานนี้มีถั่วลิสงไหมครับ','สถานีรถไฟอยู่ที่ไหน','สวัสดี นี่คือเสียงของฉัน รถไฟออกตอนห้าโมง']
rows=[]
for i,text in enumerate(cases):
 ids=front.tokens(text);style=front.style(str(models/'voicepacks.npz'),'f_mid_clear',len(ids)-2)
 ts=(C.c_int64*len(ids))(*ids);ss=(C.c_float*256)(*style);n=C.c_int();start=time.monotonic()
 p=lib.ot_wayu_generate(h,ts,len(ids),ss,C.byref(n),None);assert p and n.value>0,(text,n.value)
 a=np.ctypeslib.as_array(p,shape=(n.value,)).copy();lib.ot_wayu_audio_free(p)
 assert np.isfinite(a).all() and np.mean(a*a)>1e-6
 row=dict(text=text,phonemes=front.phonemes(text),audioSeconds=len(a)/24000,synthesisSeconds=time.monotonic()-start);rows.append(row);print(row,flush=True)
 with wave.open(str(root/f'.build/wayu-probe/phrase-{i}.wav'),'wb') as w:
  w.setnchannels(1);w.setsampwidth(2);w.setframerate(24000);w.writeframes((a.clip(-1,1)*32767).astype('<i2').tobytes())
# Exercise every speaker in the exact production graph and export local previews.
import subprocess
for voice in sorted(np.load(models/'voicepacks.npz').files):
 text='สวัสดี นี่คือเสียงของฉัน รถไฟออกตอนห้าโมง'
 ids=front.tokens(text);style=front.style(str(models/'voicepacks.npz'),voice,len(ids)-2)
 ts=(C.c_int64*len(ids))(*ids);ss=(C.c_float*256)(*style);n=C.c_int()
 p=lib.ot_wayu_generate(h,ts,len(ids),ss,C.byref(n),None);assert p and n.value>0,voice
 a=np.ctypeslib.as_array(p,shape=(n.value,)).copy();lib.ot_wayu_audio_free(p)
 assert np.isfinite(a).all() and np.mean(a*a)>1e-6
 wav=root/f'.build/wayu-probe/{voice}.wav'
 with wave.open(str(wav),'wb') as w:
  w.setnchannels(1);w.setsampwidth(2);w.setframerate(24000);w.writeframes((a.clip(-1,1)*32767).astype('<i2').tobytes())
 out=root/'assets/bundled/Voices'/f'wayu-{voice}.m4a';out.parent.mkdir(parents=True,exist_ok=True)
 subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(wav),'-af','loudnorm=I=-16:TP=-1.5:LRA=11','-c:a','aac','-b:a','128k',str(out)],check=True)
 print('preview',voice,len(a)/24000,flush=True)
# Cancellation before work, bad tokens, and too-long input must not return PCM.
lib.wt_cancel_create.restype=C.c_void_p;lib.wt_cancel_set.argtypes=[C.c_void_p];lib.wt_cancel_free.argtypes=[C.c_void_p]
flag=lib.wt_cancel_create();lib.wt_cancel_set(flag)
assert not lib.ot_wayu_generate(h,ts,len(ids),ss,C.byref(n),flag)
lib.wt_cancel_free(flag)
bad=(C.c_int64*3)(0,1000,0);assert not lib.ot_wayu_generate(h,bad,3,ss,C.byref(n),None)
assert not lib.ot_wayu_generate(h,ts,503,ss,C.byref(n),None)
lib.ot_wayu_free(h)
(root/'.build/wayu-probe/results.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
