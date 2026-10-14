import json
from pathlib import Path
import subprocess
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ModelCatalogTests(unittest.TestCase):
    def test_generated_apple_adapter_is_current(self):
        subprocess.run([sys.executable, str(ROOT/'scripts/generate-model-catalog.py'), '--check'],check=True)
    def test_primary_identity_and_platforms(self):
        data=json.loads((ROOT/'assets/catalogs/models.json').read_text())
        self.assertEqual(data['schemaVersion'],1)
        rows=data['models'];self.assertEqual(len({m['id'] for m in rows}),len(rows))
        index=next(m for m in rows if m['symbol']=='indexTranslation')
        self.assertEqual(index['sha256'],'9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713')
        self.assertEqual(index['byteCount'],5780090304)
        self.assertEqual(index['platforms'],['ios','macos','android'])
