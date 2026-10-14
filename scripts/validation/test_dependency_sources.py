"""Source collection must reject corruption and never escape its output folder."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('collector', Path(__file__).resolve().parents[1] / 'collect-dependency-sources.py')
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)


class SourceCollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = b'upstream source bytes'
        self.item = dict(file='source.tar.gz', url='https://example.invalid/source', sha256=hashlib.sha256(self.data).hexdigest())

    def response(self, data):
        stream = io.BytesIO(data)
        stream.url = self.item['url']
        return stream

    def test_verified_cache_never_uses_network(self):
        (self.root / self.item['file']).write_bytes(self.data)
        with patch.object(collector.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            collector.collect(self.item, self.root)
            collector.collect(self.item, self.root, check=True)

    def test_bad_download_preserves_existing_file(self):
        target = self.root / self.item['file']
        target.write_bytes(b'prior evidence')
        with patch.object(collector.urllib.request, 'urlopen', return_value=self.response(b'corrupt')):
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                collector.collect(self.item, self.root)
        self.assertEqual(target.read_bytes(), b'prior evidence')
        self.assertEqual(list(self.root.iterdir()), [target])

    def test_verified_download_is_committed(self):
        with patch.object(collector.urllib.request, 'urlopen', return_value=self.response(self.data)):
            collector.collect(self.item, self.root)
        self.assertEqual((self.root / self.item['file']).read_bytes(), self.data)

    def test_check_rejects_missing_and_altered_files_without_network(self):
        with patch.object(collector.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            for data in [None, b'corrupt']:
                if data is not None:
                    (self.root / self.item['file']).write_bytes(data)
                with self.assertRaisesRegex(ValueError, 'Missing or altered'):
                    collector.collect(self.item, self.root, check=True)

    def test_path_escape_and_symlink_are_rejected(self):
        for name in ['../source', '/tmp/source', '.', '']:
            with self.assertRaises(ValueError):
                collector.destination(self.root, name)
        (self.root / 'link').symlink_to(self.root / 'other')
        with self.assertRaises(ValueError):
            collector.destination(self.root, 'link')


if __name__ == '__main__':
    unittest.main()
