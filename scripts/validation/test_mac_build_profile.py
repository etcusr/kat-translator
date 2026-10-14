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
if __name__=="__main__":unittest.main()
