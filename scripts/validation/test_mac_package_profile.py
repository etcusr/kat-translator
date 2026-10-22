#!/usr/bin/env python3
"""Audit 22.10 (B15): package-macos.sh refuses an app whose build profile differs from the requested one."""
import os, plistlib, subprocess, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class PackageProfile(unittest.TestCase):
    def run_package(self, info, profile):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp)/'Kat translator.app'
            (app/'Contents').mkdir(parents=True)
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            env = dict(os.environ, KAT_MAC_APP=str(app), KAT_MAC_PROFILE=profile, KAT_MAC_SIGNING_OVERRIDE='-')
            return subprocess.run(['bash', str(ROOT/'scripts/package-macos.sh')], env=env, capture_output=True, text=True, timeout=120)

    def test_modern_app_is_not_packaged_as_compatible_download(self):
        result = self.run_package({'CFBundleShortVersionString': '0.0.0', 'CFBundleVersion': '0', 'LSMinimumSystemVersion': '27.0'}, 'macos15')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not match', result.stderr)

    def test_compatible_app_is_not_packaged_as_modern_download(self):
        result = self.run_package({'CFBundleShortVersionString': '0.0.0', 'CFBundleVersion': '0', 'LSMinimumSystemVersion': '15.0', 'KatBuildProfile': 'macos15'}, 'modern')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not match', result.stderr)

if __name__ == '__main__':
    unittest.main()
