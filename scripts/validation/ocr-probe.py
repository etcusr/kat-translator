"""Run the production C OCR bridge against pinned models and synthetic single-line images."""
import ctypes, json, pathlib, numpy as np
from PIL import Image, ImageDraw, ImageFont
root=pathlib.Path(__file__).resolve().parents[2]
lib=ctypes.CDLL(str(root/'.build/ocr-probe/libocr.dylib'))
lib.ot_ocr_load.argtypes=[ctypes.c_char_p];lib.ot_ocr_load.restype=ctypes.c_void_p
lib.ot_ocr_height.argtypes=[ctypes.c_void_p];lib.ot_ocr_height.restype=ctypes.c_int
lib.ot_ocr_run.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_float),ctypes.c_int,ctypes.POINTER(ctypes.c_int),ctypes.c_int]
lib.ot_ocr_free.argtypes=[ctypes.c_void_p]
for lang,text in [('english','Please do not add sugar'),('eslav','Пожалуйста, не добавляйте сахар')]:
    handle=lib.ot_ocr_load(str(root/f'model-store/downloads/ocr-{lang}.onnx').encode());assert handle
    font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',42)
    box=font.getbbox(text); image=Image.new('RGB',(box[2]+12,box[3]-box[1]+12),'white')
    ImageDraw.Draw(image).text((6,6-box[1]),text,font=font,fill='black')
    image.save(root/f'.build/ocr-probe/{lang}.png')
    height=lib.ot_ocr_height(handle); scaled=int(np.ceil(height*image.width/image.height));width=max(320,scaled)
    rgb=np.asarray(image.resize((scaled,height)),dtype=np.float32)
    tensor=np.zeros((3,height,width),dtype=np.float32);tensor[:,:,:scaled]=(rgb[:,:,::-1]/127.5-1).transpose(2,0,1)
    ids=(ctypes.c_int*4096)();count=lib.ot_ocr_run(handle,tensor.ctypes.data_as(ctypes.POINTER(ctypes.c_float)),width,ids,4096);assert count>0
    chars=json.loads((root/f'assets/bundled/OCR/ocr-{lang}-characters.json').read_text());prev=-1;out=''
    for i in ids[:count]:
        assert 0<=i<len(chars),(i,len(chars))
        if i and i!=prev:out+=chars[i]
        prev=i
    lib.ot_ocr_free(handle)
    print(lang,height,repr(out),flush=True); assert out.strip()==text,(text,out)
print('Native OCR bridge: both synthetic lines matched exactly')

# New Vision-language fixtures consumed by ocr-hybrid-probe.swift.
from PIL import Image, ImageDraw, ImageFont
for stem, text in [("french", "Le train part à 17h45."), ("german", "Bitte keinen Zucker hinzufügen.")]:
    picture = Image.new("RGB", (1600, 300), "white")
    ImageDraw.Draw(picture).text((50, 95), text, font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 64), fill="black")
    picture.save(root / ".build" / "ocr-probe" / (stem + ".png"))
