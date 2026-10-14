import importlib.util
import ast
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'update-animation-gallery.py'

class GallerySyncTests(unittest.TestCase):
    def test_playlist_matches_sources_and_has_no_retired_clip(self):
        root = SCRIPT.parents[1]
        assets = root / 'assets/bundled/LoadingAnimations'
        rows = json.loads((assets / 'loading-animations.json').read_text())
        ids = {row['id'] for row in rows}
        self.assertNotIn('one-beer', ids)
        self.assertEqual(len(ids), len(rows))
        tree = ast.parse((root / 'scripts/prepare-loading-animations.py').read_text())
        sources = next(ast.literal_eval(node.value) for node in tree.body
                       if isinstance(node, ast.Assign) and any(
                           isinstance(target, ast.Name) and target.id == 'SOURCES'
                           for target in node.targets))
        self.assertEqual(ids, {row[0] for row in sources})
        expected = {row['resource'] for row in rows}
        for suffix in ['mp4', 'jpg']:
            self.assertEqual(expected, {p.stem for p in assets.glob('*.' + suffix)})

    def test_add_remove_and_keep_unmanaged_files(self):
        self.assertTrue(SCRIPT.exists(), 'Persistent gallery synchronizer is missing')
        spec = importlib.util.spec_from_file_location('gallery', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            module.publish(root, {'clips/old.mp4': b'old', 'index.html': b'old page'})
            (root / 'review-notes.txt').write_text('keep this')
            module.publish(root, {'clips/new.mp4': b'new', 'index.html': b'new page'})
            self.assertFalse((root / 'clips/old.mp4').exists())
            self.assertEqual((root / 'clips/new.mp4').read_bytes(), b'new')
            self.assertEqual((root / 'review-notes.txt').read_text(), 'keep this')
            self.assertTrue(module.publish(root, {'clips/new.mp4': b'new', 'index.html': b'new page'}, check=True))
            self.assertFalse(module.publish(root, {'clips/new.mp4': b'changed', 'index.html': b'new page'}, check=True))
            self.assertEqual((root / 'clips/new.mp4').read_bytes(), b'new')

    def test_output_cannot_escape_gallery(self):
        self.assertTrue(SCRIPT.exists(), 'Persistent gallery synchronizer is missing')
        spec = importlib.util.spec_from_file_location('gallery_paths', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                module.publish(Path(folder), {'../outside.mp4': b'no'})

if __name__ == '__main__':
    unittest.main()
