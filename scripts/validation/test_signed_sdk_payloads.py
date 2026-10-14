"""A distributor signature must never mask an altered upstream SDK payload."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location('sdk_signer', Path(__file__).resolve().parents[1] / 'sign-verified-speech-sdks.py')
signer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signer)


class SignedPayloadTests(unittest.TestCase):
    def test_signature_metadata_is_allowed_but_payload_tampering_is_not(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sdk = root / 'Example.xcframework'
            sdk.mkdir()
            (sdk / 'library').write_bytes(b'upstream')
            archive = root / 'sdk.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('Example.xcframework/library', b'upstream')
            digest = signer.sha256(archive)
            original = signer.verify_payload(sdk, archive, digest)
            (sdk / '_CodeSignature').mkdir()
            (sdk / '_CodeSignature/CodeResources').write_bytes(b'seal')
            self.assertEqual(signer.verify_payload(sdk, archive, digest), original)
            (sdk / 'library').write_bytes(b'altered')
            with self.assertRaises(ValueError):
                signer.verify_payload(sdk, archive, digest)

    def test_changed_archive_and_injected_files_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sdk = root / 'Example.xcframework'
            sdk.mkdir()
            archive = root / 'sdk.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('Example.xcframework/library', b'upstream')
            with self.assertRaises(ValueError):
                signer.verify_payload(sdk, archive, '0' * 64)
            (sdk / 'library').write_bytes(b'upstream')
            (sdk / 'injected').write_bytes(b'bad')
            with self.assertRaises(ValueError):
                signer.verify_payload(sdk, archive, signer.sha256(archive))


if __name__ == '__main__':
    unittest.main()
