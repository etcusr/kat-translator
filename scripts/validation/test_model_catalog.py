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

    def test_ios_whisper_q8_keeps_other_platforms_on_existing_f16(self):
        rows=json.loads((ROOT/'assets/catalogs/models.json').read_text())['models']
        default=next(m for m in rows if m['symbol']=='turbo')
        ios=default | default.get('platformOverrides',{}).get('ios',{})
        self.assertEqual(ios['id'],'whisper-large-v3-turbo-q8_0')
        self.assertEqual(ios['byteCount'],874188075)
        self.assertEqual(ios['sha256'],'317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1')
        self.assertIn('/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q8_0.bin',ios['remoteURL'])
        self.assertEqual(default['id'],'whisper-large-v3-turbo-f16')
        self.assertEqual(default['byteCount'],1624555275)
        self.assertEqual(default['sha256'],'1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69')
        self.assertEqual(set(default.get('platformOverrides',{})),{'ios'})
