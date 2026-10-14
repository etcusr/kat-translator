"""License assembly must preserve text and reject altered source notices."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'assemble-ios-notices.py'


class IOSNoticesTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('ios_notices', SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'LICENSE').write_text('Own license\n')
        data = 'Copyright © Example\r\nRedistribution allowed.\r\n'.encode()
        (self.root / 'dependency.txt').write_bytes(data)
        (self.root / 'manifest.json').write_text(json.dumps([
            {'file': 'dependency.txt', 'sha256': hashlib.sha256(data).hexdigest()}
        ]))
        self.module.ROOT = self.module.SOURCE = self.root

    def test_crlf_source_survives_text_readback(self):
        result = self.module.assemble()
        out = self.root / 'combined.txt'
        out.write_text(result)
        self.assertEqual(out.read_text(), result)
        self.assertIn('Copyright © Example\nRedistribution allowed.', result)
        self.assertIn('Own license', result)

    def test_modified_license_is_rejected(self):
        (self.root / 'dependency.txt').write_text('Different license')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            self.module.assemble()

    def test_missing_license_is_rejected(self):
        (self.root / 'dependency.txt').unlink()
        with self.assertRaises(FileNotFoundError):
            self.module.assemble()


if __name__ == '__main__':
    unittest.main()
