"""Offline Wayu frontend. Called with a string, never evaluated as Python code."""
import os, json, re
from pathlib import Path
os.environ['PYTHAINLP_OFFLINE']='1'
os.environ['PYTHAINLP_READ_ONLY']='1'
os.environ['KOKORO_THAI_NO_RUST']='1'
from kokoro_thai.g2p import ThaiG2P
class MobileThaiG2P(ThaiG2P):
    # The Thai path is unchanged. Embedded English uses Misaki's shipped dictionary;
    # contextual POS disambiguation needs spaCy and is deliberately not claimed here.
    def _en_to_tokens(self, text, drops=None):
        if not hasattr(self, '_english'):
            self._english=json.loads((Path(__file__).parent/'english-lexicon.json').read_text(encoding='utf-8'))
        out=[]
        for word in re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", text):
            value=self._english.get(word) or self._english.get(word.lower())
            if isinstance(value,dict):value=value.get('DEFAULT')
            if not isinstance(value,str) or not value:
                raise ValueError('English word has no pronunciation: '+word)
            if any(c not in self.vocab for c in value):raise ValueError('Invalid English phoneme')
            out.append(value)
        return ' '.join(out)
_g2p=MobileThaiG2P()
def phonemes(text):
    if not isinstance(text,str) or '\0' in text or len(text)>2000:
        raise ValueError('Invalid speech text')
    result, drops, symbols=_g2p.phonemize_report(text)
    if drops or any(c.isalpha() or c.isdigit() for c in symbols) or not result.strip():
        raise ValueError('Cannot pronounce this text without dropping words')
    return result

def tokens(text):
    result=phonemes(text)
    ids=[_g2p.vocab[c] for c in result]
    if len(ids)>500:raise OverflowError('Speech fragment too long')
    return [0,*ids,0]

# Read only this pinned NPY shape and float type; no numpy, pickle or executable
# code is accepted from a downloaded voice package.
def style(pack_path, voice, length):
    import zipfile, struct, ast
    with zipfile.ZipFile(pack_path) as z:
        member=z.getinfo(voice+'.npy')
        if member.file_size>600000:raise ValueError('Voice pack too large')
        raw=z.read(member)
    if raw[:8]!=b'\x93NUMPY\x01\x00':raise ValueError('Invalid voice pack')
    size=struct.unpack_from('<H',raw,8)[0]
    header=ast.literal_eval(raw[10:10+size].decode('ascii'))
    if header!={'descr':'<f4','fortran_order':False,'shape':(512,1,256)}:
        raise ValueError('Invalid voice shape')
    if len(raw)!=10+size+512*256*4:raise ValueError('Incomplete voice pack')
    index=max(0,min(511,length-1))
    return struct.unpack_from('<256f',raw,10+size+index*1024)
