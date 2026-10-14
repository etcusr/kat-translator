import importlib.util, sys, types, unittest
from pathlib import Path
p=Path(__file__).resolve().parents[2]/'shared/native/IndexMLX/index_mlx.py'
spec=importlib.util.spec_from_file_location('index_mlx',p);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class Tokenizer:
 eos_token_ids={0}
 def encode(self,text,add_special_tokens=False): return list(range(len(text)))
 def decode(self,tokens): return 'translated'
class MX:
 def synchronize(self): pass
class Generator:
 instances=[]; reason='stop'
 def __init__(self,*a,**kw): self.closed=False;self.steps=0;self.kw=kw;self.__class__.instances.append(self)
 def insert(self,*a): pass
 def next(self):
  self.steps+=1
  return None,[types.SimpleNamespace(token=1,finish_reason=self.reason)]
 def close(self):self.closed=True
class RuntimeTests(unittest.TestCase):
 def setUp(self):
  Generator.instances=[];Generator.reason='stop'
  self.engine=module.Engine.__new__(module.Engine);self.engine.tokenizer=Tokenizer();self.engine.mx=MX();self.engine.model=object()
  self.old=sys.modules.get('mlx_lm.generate');sys.modules['mlx_lm.generate']=types.SimpleNamespace(BatchGenerator=Generator)
 def tearDown(self):
  if self.old is None:sys.modules.pop('mlx_lm.generate',None)
  else:sys.modules['mlx_lm.generate']=self.old
 def test_cancel_before_input_limit(self):
  self.assertEqual(self.engine.run('', 'x'*2000, '',lambda: True),(2,'',-1.))
  self.assertEqual(Generator.instances,[])
 def test_no_partial_result_on_output_limit_then_reuse(self):
  Generator.reason='length';self.assertEqual(self.engine.run('','hello','',lambda: False),(1,'',-1.))
  self.assertTrue(Generator.instances[-1].closed)
  Generator.reason='stop';self.assertEqual(self.engine.run('','hello','',lambda: False)[:2],(0,'translated'))
 def test_cancellation_after_gpu_round_then_reuse(self):
  calls=iter([False,False,True]);self.assertEqual(self.engine.run('','hello','',lambda:next(calls)),(2,'',-1.))
  self.assertTrue(Generator.instances[-1].closed)
  self.assertEqual(self.engine.run('','hello','',lambda:False)[:2],(0,'translated'))
 def test_full_context_response_budget(self):
  self.engine.run('','x'*1536,'',lambda:False)
  self.assertEqual(Generator.instances[-1].kw['max_tokens'],512)
  self.assertEqual(self.engine.run('','x'*1537,'',lambda:False),(1,'',-1.))
if __name__=='__main__':unittest.main()
