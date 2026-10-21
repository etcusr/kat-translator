"""Exercise the iOS task owner's lifecycle with controlled system task APIs."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ContinuedDownloadTests(unittest.TestCase):
    def test_progress_completion_rejection_and_expiration(self):
        path = ROOT / 'apps/ios/Models/DownloadContinuedTask.swift'
        source = path.read_text()
        source = source.replace('import BackgroundTasks', '').replace('import OfflineCore', '')
        source += '\n' + (ROOT / 'shared/packages/OfflineCore/Sources/OfflineCore/DownloadProgress.swift').read_text()
        source += '\n' + (ROOT / 'scripts/validation/fixtures/continued_download.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='kat-continued-') as folder:
            swift, binary = Path(folder)/'probe.swift', Path(folder)/'probe'
            swift.write_text(source)
            build = subprocess.run(['swiftc', '-module-cache-path', folder+'/modules', '-parse-as-library', str(swift), '-o', str(binary)], text=True, capture_output=True)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(binary)], text=True, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertIn('PASS: continued download lifecycle', run.stdout)
