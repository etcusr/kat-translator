import importlib.util, unittest
from pathlib import Path
p=Path(__file__).resolve().parents[1]/"mac-build-profile.py"
spec=importlib.util.spec_from_file_location("profile",p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ProfileTests(unittest.TestCase):
 def test_modern_output_matches_existing_release(self):
  x=m.profile("modern");self.assertEqual(x["minimum"],"27.0");self.assertEqual(x["suffix"],"");self.assertEqual(x["runtime"],"index-mlx")
 def test_compat_uses_same_model_and_distinct_runtime_output(self):
  x=m.profile("macos15");self.assertEqual(x["minimum"],"15.0");self.assertEqual(x["suffix"],"-macos15-26");self.assertEqual(x["runtime"],"index-mlx-macos15");self.assertEqual(x["modelPackage"],m.profile("modern")["modelPackage"])
 def test_unknown_profile_rejected(self):
  with self.assertRaises(ValueError):m.profile("macos14")
 def test_store_runtime_is_separate_and_keeps_models(self):
  for name in ('modern','macos15'):
   direct=m.profile(name);store=m.profile(name,store=True)
   self.assertNotEqual(direct['python'],store['python'])
   self.assertIn('no-tls',store['python'])
   self.assertEqual({k:v for k,v in direct.items() if k!='python'}, {k:v for k,v in store.items() if k!='python'})
if __name__=="__main__":unittest.main()
