import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('mtp_profile',Path(__file__).resolve().parents[1]/'android'/'summarize-mtp-profile.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


class MtpProfile(unittest.TestCase):
    def test_checkpoint_tail_is_prefill_not_generation(self):
        text='''slot processing task, is_child=0
KAT_MTP_STAGE name=target tokens=42 ms=100
KAT_MTP_STAGE name=process tokens=42 ms=10
KAT_MTP_STAGE name=target tokens=4 ms=40
KAT_MTP_STAGE name=process tokens=4 ms=5
KAT_MTP_STAGE name=begin tokens=46 ms=1
KAT_MTP_STAGE name=draft tokens=0 ms=20
KAT_MTP_STAGE name=target tokens=3 ms=30
KAT_MTP_STAGE name=process tokens=3 ms=2
slot total time = 208
'''
        report=module.summarize(text)['requests'][0]
        self.assertEqual(report['stageMs']['prefill.target'],140)
        self.assertEqual(report['stageMs']['prefill.process'],15)
        self.assertEqual(report['stageMs']['decode.target'],30)
        self.assertEqual(report['stageMs']['decode.draft'],20)
        self.assertTrue(report['complete'])

    def test_multiple_requests_and_incomplete_last_request(self):
        text=('slot processing task, is_child=0\nKAT_MTP_STAGE name=target tokens=46 ms=10\n'
              'slot total time = 10\nslot processing task, is_child=0\nKAT_MTP_STAGE name=target tokens=46 ms=20\n')
        requests=module.summarize(text)['requests']
        self.assertEqual(len(requests),2)
        self.assertFalse(requests[1]['complete'])
        self.assertEqual(requests[1]['stageMs']['prefill.target'],20)

    def test_missing_or_nonfinite_measurements_are_rejected(self):
        for text in ['', 'slot processing task, is_child=0\nKAT_MTP_STAGE name=draft tokens=0 ms=nan']:
            with self.assertRaises(ValueError):module.summarize(text)
