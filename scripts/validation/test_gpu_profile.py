"""Guard units and request/dispatch boundaries in the performance evidence."""
import importlib.util
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "android/summarize-gpu-profile.py"
SPEC = importlib.util.spec_from_file_location("gpu_profile", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProfileEvidence(unittest.TestCase):
    def test_multiple_dispatches_and_incomplete_request(self):
        log = """KAT_PROFILE_BEGIN
Vulkan Timings:
MUL_MAT q4_K m=12288 n=46 k=4096: 64 x 17417.6 us = 1.11472e+06 us (265.82 GFLOPS/s)
ADD: 2 x 50 us = 100 us
Total time: 1.11482e+06 us.
Vulkan Timings:
MUL_MAT_VEC q6_K m=248320 n=1 k=4096: 1 x 37732 us = 37732 us
KAT_STAGE prefill_submit 1144.900 ms 1 calls
KAT_STAGE decode_submit 41.350 ms 14 calls
KAT_PROFILE_END
KAT_PROFILE_BEGIN
KAT_STAGE tokenize 0.5 ms 1 calls
"""
        rows = MODULE.summarize(log)["requests"]
        self.assertEqual(len(rows), 2)
        self.assertTrue(rows[0]["complete"])
        self.assertFalse(rows[1]["complete"])
        self.assertAlmostEqual(rows[0]["dispatches"][0]["totalMs"], 1114.82)
        self.assertAlmostEqual(rows[0]["dispatches"][1]["totalMs"], 37.732)
        self.assertEqual(rows[0]["wallStages"]["decode_submit"]["calls"], 14)
        self.assertEqual(rows[1]["dispatches"], [])

    def test_missing_profile_is_not_successful_empty_report(self):
        with self.assertRaises(ValueError):
            MODULE.summarize("GPU unavailable\n")
