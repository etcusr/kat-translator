import importlib.util,sys,unittest
from pathlib import Path
P=Path(__file__).resolve().parents[2]/'shared/native/OpusGPU/opus_gpu.py'
spec=importlib.util.spec_from_file_location('opus_gpu',P);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class Contracts(unittest.TestCase):
 def test_all_six_directions_and_literal_text(self):
  for language,tag in [('ru','rus'),('uk','ukr'),('be','bel')]:
   self.assertEqual(mod.request_input('en',language,'Hello\nworld'),('en-zle','>>'+tag+'<< Hello\nworld'))
   self.assertEqual(mod.request_input(language,'en','Text'),('zle-en','Text'))
 def test_unsupported_pair_is_not_silent_pivot(self):
  for pair in [('ru','uk'),('en','de'),('auto','en'),('ru','ru')]:
   with self.assertRaises(ValueError):mod.request_input(*pair,'text')
 def test_complete_output_requires_eos_below_limit(self):
  self.assertTrue(mod.complete([99,4,0],0))
  self.assertFalse(mod.complete([99,4],0))
  self.assertFalse(mod.complete([99]*512+[0],0))
class Worker(unittest.TestCase):
 # Audit 22.10 (B25): both direction models stay loaded; a dialogue RU<->EN reloaded a 480 MB model every turn.
 def test_direction_models_stay_loaded(self):
  engine=object.__new__(mod.Engine);engine.models={};loads=[]
  engine.load=lambda direction:loads.append(direction) or direction
  for direction in ('en-zle','zle-en','en-zle','zle-en'):self.assertEqual(engine.model_for(direction),direction)
  self.assertEqual(loads,['en-zle','zle-en'])
 # Audit 22.10 (B25): a cancel line stops the running request by id; the worker keeps serving.
 def test_cancel_stops_running_request_and_worker_continues(self):
  import io,json,os,threading,time
  class Fake:
   stopped=staticmethod(lambda:False)
   def count(self,request):return {'code':0,'count':1}
   def run(self,request):
    end=time.monotonic()+10
    while request['text']=='slow' and not self.stopped() and time.monotonic()<end:time.sleep(0.005)
    return {'code':2} if self.stopped() else {'code':0,'text':'ok'}
  read,write=os.pipe();stdin=os.fdopen(read,'rb');requests=os.fdopen(write,'wb',buffering=0)
  lines=[];out=type('Out',(),{'write':lambda self,text:lines.append(text),'flush':lambda self:None})()
  threading.Thread(target=mod.serve,args=(Fake(),stdin,out),daemon=True).start()
  send=lambda **request:requests.write((json.dumps(request)+'\n').encode())
  def reply(count):
   end=time.monotonic()+5
   while sum(text.count('\n') for text in lines)<count and time.monotonic()<end:time.sleep(0.005)
   return [json.loads(line) for line in ''.join(lines).splitlines()][count-1]
  self.assertTrue(reply(1)['ready'])
  send(command='run',id=1,text='slow',source='en',target='ru');time.sleep(0.1);start=time.monotonic()
  send(command='cancel',id=1);self.assertEqual(reply(2),{'code':2,'id':1});self.assertLess(time.monotonic()-start,1)
  send(command='run',id=2,text='fast',source='en',target='ru');self.assertEqual(reply(3),{'code':0,'text':'ok','id':2})
  send(command='cancel',id=3);send(command='run',id=3,text='slow',source='en',target='ru');self.assertEqual(reply(4),{'code':2,'id':3})
  send(command='cancel',id=1);send(command='count',id=4,text='x',source='en',target='ru');self.assertEqual(reply(5),{'code':0,'count':1,'id':4})
  send(command='nope',id=5);self.assertEqual(reply(6),{'code':-1,'id':5})
  requests.close()
if __name__=='__main__':unittest.main()
