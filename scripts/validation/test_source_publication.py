import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('source_publication', Path(__file__).parents[1] / 'package-dependency-sources.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SourcePublicationTests(unittest.TestCase):
    def test_packages_exact_inputs_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'input'
            source.mkdir()
            entries = []
            for name in ['one.txt', 'two.txt']:
                data = name.encode()
                (source / name).write_bytes(data)
                entries.append(dict(file=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
            (source / 'private.txt').write_text('not locked')
            lock = root / 'lock.json'
            lock.write_text(json.dumps(dict(archives=entries)))
            result = module.package(lock, source, root / 'out', limit=8)
            self.assertEqual(result['inputCount'], 2)
            self.assertEqual(len(result['parts']), 2)
            self.assertEqual({f for p in result['parts'] for f in p['inputs']}, {'one.txt', 'two.txt'})
            with self.assertRaises(FileExistsError):
                module.package(lock, source, root / 'out', limit=8)
            (source / 'one.txt').write_text('changed')
            with self.assertRaises(ValueError):
                module.package(lock, source, root / 'bad')
            self.assertFalse((root / 'bad').exists())

    def test_rejects_traversal_and_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = b'input'
            (root / 'original').write_bytes(data)
            (root / 'link').symlink_to(root / 'original')
            lock = root / 'lock.json'
            for name in ['../original', '/original', 'link']:
                lock.write_text(json.dumps(dict(archives=[dict(file=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest())])))
                with self.assertRaises(ValueError):
                    module.package(lock, root, root / 'out')
                self.assertFalse((root / 'out').exists())
