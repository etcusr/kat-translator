"""Run the production cancellation method with a controlled URLSession double."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class DownloadCancelTests(unittest.TestCase):
    def test_paused_download_disposes_system_resume_file(self):
        source = (ROOT / 'shared/apple/Models/ModelDownloader.swift').read_text()
        method = source[source.index('    func cancel() async {'):source.index('    func clearInstalledReference()')]
        fixture = (ROOT / 'scripts/validation/fixtures/download_cancel.swift').read_text().replace('// PRODUCTION_CANCEL', method)
        with tempfile.TemporaryDirectory(prefix='kat-cancel-') as folder:
            swift, binary = Path(folder)/'probe.swift', Path(folder)/'probe'
            swift.write_text(fixture)
            result = subprocess.run(['swiftc', '-module-cache-path', folder+'/modules', '-parse-as-library', str(swift), '-o', str(binary)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('PASS: cancel disposes paused transfer', result.stdout)
