"""Run the production ActivityKit scheduler on macOS with a controlled API double.

This verifies async ordering, not iOS suspension or actual Island rendering.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DownloadActivityTests(unittest.TestCase):
    def test_publication_is_drained_before_background_completion(self):
        files = [
            ROOT / 'apps/ios/Models/DownloadLiveActivity.swift',
            ROOT / 'apps/ios/widget/DownloadActivityAttributes.swift',
            ROOT / 'shared/packages/OfflineCore/Sources/OfflineCore/DownloadProgress.swift',
        ]
        source = '\n'.join(p.read_text() for p in files)
        for module in ['ActivityKit', 'UIKit', 'OfflineCore']:
            source = source.replace('import ' + module, '')
        source = source.replace('UserDefaults.standard', 'testDefaults')
        fixture = (ROOT / 'scripts/validation/fixtures/download_activity.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='kat-live-activity-') as folder:
            swift = Path(folder) / 'probe.swift'
            binary = Path(folder) / 'probe'
            swift.write_text(source + '\n' + fixture)
            compiled = subprocess.run(['swiftc', '-module-cache-path', str(Path(folder) / 'modules'), '-parse-as-library', str(swift), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=35)
            self.assertIn('PASS: publication ordering, latest revision, completion', result.stdout)


if __name__ == '__main__':
    unittest.main()
