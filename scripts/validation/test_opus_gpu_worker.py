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
if __name__=='__main__':unittest.main()
