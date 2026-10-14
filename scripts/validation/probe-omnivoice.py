#!/usr/bin/env python3
"""Bounded native smoke tests. Nonzero audio is not a pronunciation-quality verdict."""
import json,pathlib,re,subprocess
R=pathlib.Path(__file__).resolve().parents[2]; O=R/'.build/omnivoice'; D=R/'docs/research/omnivoice-2026-10-07'
texts=json.loads((R/'docs/research/tts-round2-2026-10-07/probe-texts.json').read_text())
for file in ['multilingual-voice-previews.c','speech-expansion-previews.c']:
 s=(R/'scripts/validation'/file).read_text()
 arrays=[re.findall(r'"([^"\n]*)"',re.search(r'const char \*'+key+r'\[\]\s*=\s*\{(.*?)\};',s,re.S).group(1)) for key in ['codes','texts']]
 texts.update(dict(zip(*arrays)))
texts.update({
 'en':'Hello! How are you?', 'ru':'Здравствуйте! Как у вас дела?',
 'th':'สวัสดีครับ วันนี้อากาศดีมาก คุณสบายดีไหมครับ',
 'ms':'Selamat pagi! Apa khabar?', 'bs':'Dobar dan. Gdje je najbliža željeznička stanica?',
 'az':'Salam! Necəsiniz?', 'mk':'Добар ден! Како сте?', 'gl':'Ola! Como estás?',
 'ary':'السلام عليكم، كيف داير؟', 'be':'Добры дзень! Як вашы справы?', 'af':'Goeie môre! Hoe gaan dit?',
 'nn':'God morgon! Korleis har du det?', 'uz':'Assalomu alaykum! Ahvolingiz qanday?',
 'si':'ආයුබෝවන්. ඔබට කොහොමද?', 'arz':'صباح الخير، إزيك؟', 'ps':'سلامونه، تاسو څنګه یاست؟',
 'ga':'Dia duit! Conas atá tú?', 'ckb':'سڵاو، چۆنیت؟', 'mt':'Bonġu! Kif inti?',
 'yue':'你好！你今日點呀？', 'bew':'Selamet pagi! Ape kabar?', 'am':'ሰላም። እንዴት ነህ?',
 'fy':'Goeiemoarn! Hoe giet it mei dy?', 'eo':'Saluton! Kiel vi fartas?', 'ars':'السلام عليكم، كيف حالك؟',
 'sd':'سلام، توهان ڪيئن آهيو؟', 'xh':'Molo! Unjani?', 'tk':'Salam! Ýagdaýyňyz nähili?',
 'yi':'אַ גוטן טאָג! ווי גייט עס אייך?', 'mi':'Kia ora! Kei te pēhea koe?', 'ug':'ياخشىمۇسىز! ئەھۋالىڭىز قانداق؟',
 'zu':'Sawubona! Unjani?', 'ig':'Ndewo! Kedu ka ị mere?', 'haw':'Aloha! Pehea ʻoe?',
 'lus':'Chibai! I dam em?', 'rm':'Bun di! Co vai?', 'ti':'ሰላም። ከመይ ኣለኻ?',
 'ast':'Bonos díes! ¿Cómo tas?', 'oc':'Bonjorn! Cossí vas?', 'anp':'प्रणाम। तोरा केना छौ?',
 'apc':'مرحبا، كيفك اليوم؟', 'nap':'Bongiorno! Comme staje?', 'hsb':'Dobry dźeń! Kak so wam wjedźe?'
})
mapping=json.loads((D/'language-map.json').read_text());results=[]
(D/'probe-texts.json').write_text(json.dumps({c:texts[c] for c in mapping},ensure_ascii=False,indent=2)+'\n')
for code,language in mapping.items():
 resultfile=O/(code+'-catalog-result.json');text=texts[code]
 if resultfile.exists() and json.loads(resultfile.read_text()).get('text')==text:
  results.append(json.loads(resultfile.read_text()));continue
 log=O/(code+'-catalog.log');audio=O/('omnivoice-q8-base-'+code+'-preview.wav')
 with log.open('w') as f:
  try:p=subprocess.run([str(O/'probe'),str(R/'model-store/downloads/omnivoice/omnivoice-base-Q8_0.gguf'),str(R/'model-store/downloads/omnivoice/omnivoice-tokenizer-Q8_0.gguf'),language,text,str(audio)],stdout=f,stderr=subprocess.STDOUT,timeout=90);status=p.returncode
  except subprocess.TimeoutExpired:status=124
 result={'code':code,'text':text,'runtimeLanguage':language,'status':'failed','exitCode':status}
 if status==0:
  result.update(json.loads(log.read_text().splitlines()[-1]));result['status']='smoke-passed'
 resultfile.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');results.append(result)
 print(code,result['status'],result.get('audioSeconds'),flush=True)
(D/'catalog-probes.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
