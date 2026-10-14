"""Clean and incremental iOS packaging must exclude both OpenSSL extensions."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PythonPruningTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('pruning', ROOT / 'scripts/prune-ios-python.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Test.app'
        self.lib = self.app / 'python/lib/python3.13/lib-dynload'
        self.lib.mkdir(parents=True)

    def test_clean_copy_removes_openssl_but_keeps_hash_fallbacks(self):
        for name in ('_ssl', '_hashlib', '_md5', '_sha1', '_sha2', '_sha3', '_blake2', '_ssl_other'):
            (self.lib / (name + '.cpython-313-iphoneos.so')).write_bytes(b'binary')
        (self.lib / '_ssl.xcprivacy').write_bytes(b'manifest')
        self.module.prune(self.app)
        names = {p.name.split('.')[0] for p in self.lib.iterdir()}
        self.assertEqual(names, {'_md5', '_sha1', '_sha2', '_sha3', '_blake2', '_ssl_other'})

    def test_incremental_copy_removes_old_frameworks_and_placeholders(self):
        for name in ('_ssl', '_hashlib', '_sha2'):
            framework = self.app / 'Frameworks' / (name + '.framework')
            framework.mkdir(parents=True)
            (framework / name).write_bytes(b'signed binary')
            (self.lib / (name + '.cpython-313-iphonesimulator.fwork')).write_text('framework')
        self.module.prune(self.app)
        self.module.prune(self.app)
        self.assertEqual([p.name for p in (self.app / 'Frameworks').iterdir()], ['_sha2.framework'])
        self.assertEqual([p.name for p in self.lib.iterdir()], ['_sha2.cpython-313-iphonesimulator.fwork'])

    def test_missing_stdlib_fails_without_removing_frameworks(self):
        framework = self.app / 'Frameworks/_ssl.framework'
        framework.mkdir(parents=True)
        self.lib.rmdir()
        with self.assertRaises(RuntimeError):
            self.module.prune(self.app)
        self.assertTrue(framework.is_dir())

    def test_symlink_outside_bundle_is_rejected_before_deletion(self):
        outside = Path(self.temp.name) / 'vendor'
        outside.mkdir()
        binary = outside / '_ssl.so'
        binary.write_bytes(b'vendor binary')
        self.lib.rmdir()
        self.lib.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            self.module.prune(self.app)
        self.assertTrue(binary.exists())


if __name__ == '__main__':
    unittest.main()
