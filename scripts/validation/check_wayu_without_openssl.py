#!/usr/bin/env python3
"""Run packaged Wayu sources on the host with OpenSSL and network access blocked.

Usage: python3 -B -I -S scripts/validation/check_wayu_without_openssl.py APP [STYLES.npz]
This checks Python call paths, not execution of the iOS interpreter or audio output.
"""
import sys
sys.dont_write_bytecode = True
import importlib.abc
import importlib.util
from pathlib import Path

APP = Path(sys.argv[1]).resolve()
STYLE_PACK = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
ROOT = Path(__file__).resolve().parents[2]


class NoOpenSSL(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname in ('_ssl', '_hashlib'):
            raise ModuleNotFoundError('OpenSSL deliberately excluded', name=fullname)


sys.meta_path.insert(0, NoOpenSSL())
for name in ('ssl', '_ssl', 'hashlib', '_hashlib'):
    sys.modules.pop(name, None)


def deny_network(event, args):
    if event in ('socket.connect', 'socket.getaddrinfo', 'urllib.Request', 'subprocess.Popen'):
        raise RuntimeError('Offline test attempted network or child-process access: ' + event)


sys.addaudithook(deny_network)
sys.path.insert(0, str(APP / 'WayuPython'))
# Use the shipped hashlib Python source, with the host's built-in hash extensions.
hashlib_source = next((APP / 'python/lib').glob('python3.*/hashlib.py'))
spec = importlib.util.spec_from_file_location('hashlib', hashlib_source)
hashlib = importlib.util.module_from_spec(spec)
sys.modules['hashlib'] = hashlib
spec.loader.exec_module(hashlib)

import math
import struct
import tempfile
import unittest
import zipfile
from wayu_frontend import style


class WithoutOpenSSLTests(unittest.TestCase):
    def test_openssl_extensions_cannot_load(self):
        for name in ('_ssl', '_hashlib', 'ssl'):
            with self.assertRaises(ImportError):
                __import__(name)
        self.assertIsNone(hashlib._hashlib)

    def test_hashlib_fallback_known_vectors(self):
        expected = {
            'md5': '900150983cd24fb0d6963f7d28e17f72',
            'sha1': 'a9993e364706816aba3e25717850c26c9cd0d89d',
            'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
            'sha3_256': '3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532',
        }
        for algorithm, value in expected.items():
            self.assertEqual(hashlib.new(algorithm, b'abc').hexdigest(), value)
            self.assertEqual(getattr(hashlib, algorithm)(b'abc').hexdigest(), value)

    def test_compressed_style_pack_and_bounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack = Path(tmp) / 'styles.npz'
            header = repr({'descr': '<f4', 'fortran_order': False, 'shape': (512, 1, 256)}).encode('ascii')
            raw = b'\x93NUMPY\x01\x00' + struct.pack('<H', len(header)) + header
            raw += b''.join(struct.pack('<256f', *([float(i)] * 256)) for i in range(512))
            with zipfile.ZipFile(pack, 'w', zipfile.ZIP_DEFLATED) as archive:
                archive.writestr('test.npy', raw)
            for length, index in ((0, 0), (2, 1), (512, 511), (999, 511)):
                self.assertEqual(style(pack, 'test', length), (float(index),) * 256)

    @unittest.skipIf(STYLE_PACK is None, 'No downloaded style pack supplied')
    def test_downloaded_style_pack(self):
        for length in (1, 20, 100, 512):
            result = style(STYLE_PACK, 'f_mid_clear', length)
            self.assertEqual(len(result), 256)
            self.assertTrue(all(math.isfinite(value) for value in result))


suite = unittest.defaultTestLoader.discover(str(ROOT / 'shared/native/Wayu'), pattern='test_frontend.py')
suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(WithoutOpenSSLTests))
result = unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(not result.wasSuccessful())
