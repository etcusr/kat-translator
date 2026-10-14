import tempfile
import unittest
from pathlib import Path
import zipfile
from check_release_notices import verify


class PackagedNoticesTests(unittest.TestCase):
    def test_zip_paths_and_stale_content(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ['assets/ThirdPartyNotices.txt', 'Payload/Kat.app/ThirdPartyNotices.txt']:
                archive = Path(directory) / 'app.zip'
                with zipfile.ZipFile(archive, 'w') as output:
                    output.writestr(name, b'reviewed notices')
                self.assertEqual(len(verify(archive, b'reviewed notices')), 64)
                with self.assertRaisesRegex(ValueError, 'differ'):
                    verify(archive, b'new notices')

    def test_nested_resource_does_not_hide_missing_app_notice(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'app.zip'
            with zipfile.ZipFile(archive, 'w') as output:
                output.writestr('Payload/Kat.app/Frameworks/Vendor/ThirdPartyNotices.txt', b'text')
            with self.assertRaisesRegex(ValueError, 'top-level'):
                verify(archive, b'text')

    def test_mac_and_ios_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['ThirdPartyNotices.txt', 'Contents/Resources/ThirdPartyNotices.txt']:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'notice')
                self.assertEqual(len(verify(root, b'notice')), 64)
                target.unlink()


if __name__ == '__main__':
    unittest.main()
