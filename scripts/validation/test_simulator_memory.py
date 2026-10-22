"""The UI runner must not overlap native Kat with the iPhone simulator."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('kat_simulator_runner',Path(__file__).resolve().parents[1]/'simulator/run.py')
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
class SimulatorMemoryTests(unittest.TestCase):
    def test_native_app_and_orphan_worker_block_start(self):
        for process in ('/Applications/Kat translator.app/Contents/MacOS/Kat translator',
                        '/tmp/test/Kat translator.app/Contents/MacOS/OpusPython'):
            with self.subTest(process=process),patch.object(runner,'capture',return_value=process):
                with self.assertRaisesRegex(SystemExit,'Quit Kat on Mac'):
                    runner.require_mac_kat_closed()
    def test_unrelated_app_does_not_block(self):
        with patch.object(runner,'capture',return_value='/Applications/Other.app/Contents/MacOS/Other'):
            runner.require_mac_kat_closed()
if __name__=='__main__':unittest.main()
