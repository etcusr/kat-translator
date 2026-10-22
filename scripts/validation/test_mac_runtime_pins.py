#!/usr/bin/env python3
"""Audit 22.10 (B16, E2): Mac runtime inputs are pinned in the repository, never by a server response,
and no build input is taken from the build host's Homebrew installation."""
import ast, re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class MacRuntimePins(unittest.TestCase):
    def test_compatible_runtime_hashes_are_pinned_constants(self):
        source = (ROOT/'scripts/prepare-macos15-runtime.py').read_text()
        self.assertNotIn('pypi.org/pypi/', source, 'expected hash must not come from the PyPI JSON API')
        self.assertNotIn('api.github.com', source, 'expected hash must not come from the GitHub API')
        tree = ast.parse(source)
        self.assertFalse([n for n in ast.walk(tree) if isinstance(n, ast.Assert)], 'assert is removed by python -O')
        self.assertGreaterEqual(len(re.findall(r"'[0-9a-f]{64}'", source)), 4)

    def test_build_inputs_do_not_use_homebrew_python(self):
        for script in ['scripts/bundle-macos-runtimes.py', 'scripts/generate-macos-project.py', 'scripts/build-macos-runtimes.sh']:
            text = (ROOT/script).read_text()
            code = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
            self.assertNotIn('/opt/homebrew', code, script)

    def test_python_bytecode_is_precompiled_into_the_bundle(self):
        text = (ROOT/'scripts/bundle-macos-runtimes.py').read_text()
        self.assertIn('compileall', text)
        self.assertIn('checked-hash', text)

if __name__ == '__main__':
    unittest.main()
