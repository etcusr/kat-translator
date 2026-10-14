import importlib.util,hashlib,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class BlobStoreTests(unittest.TestCase):
    def setUp(self):
        spec=importlib.util.spec_from_file_location('blobs',ROOT/'scripts/models/blob_store.py');self.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.m)
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
    def test_adopt_moves_without_copy_and_repeat_is_idempotent(self):
        source=self.root/'model.gguf';source.write_bytes(b'weights');inode=source.stat().st_ino
        sha=hashlib.sha256(b'weights').hexdigest();target=self.m.adopt(source,self.root/'store',sha,7)
        self.assertTrue(source.is_symlink());self.assertEqual(target.stat().st_ino,inode)
        self.assertEqual(self.m.adopt(source,self.root/'store',sha,7),target)
        self.assertEqual(sum(p.stat().st_size for p in (self.root/'store').iterdir()),7)
    def test_same_filename_different_content_has_different_blob(self):
        results=[]
        for name,content in [('ios',b'one'),('android',b'two')]:
            p=self.root/name/'model.gguf';p.parent.mkdir();p.write_bytes(content)
            results.append(self.m.adopt(p,self.root/'store',hashlib.sha256(content).hexdigest(),3))
        self.assertNotEqual(*results)
    def test_invalid_digest_never_replaces_original(self):
        p=self.root/'original';p.write_bytes(b'good')
        with self.assertRaises(ValueError):self.m.adopt(p,self.root/'store','a'*64,4)
        self.assertEqual(p.read_bytes(),b'good');self.assertFalse(p.is_symlink())
    def test_existing_corrupt_blob_is_rejected(self):
        p=self.root/'original';p.write_bytes(b'good');sha=hashlib.sha256(b'good').hexdigest()
        store=self.root/'store';store.mkdir();(store/sha).write_bytes(b'evil')
        with self.assertRaises(ValueError):self.m.adopt(p,store,sha,4)
        self.assertFalse(p.is_symlink())
