"""Catch telemetry initialization before Kat's opt-out, including failed setup."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InferencePrivacyTests(unittest.TestCase):
    def build_probe(self, directory, fail=False):
        sources = ['shared/native/app/Camera/OCRRuntime.c',
                   'shared/native/app/Speech/WayuSpeechRuntime.c',
                   'shared/native/app/Speech/SpeechRuntime.c',
                   'scripts/validation/fixtures/inference_privacy_probe.c']
        flags = ['clang', '-I' + str(ROOT), '-I' + str(ROOT / 'Dependencies/build/macos/headers')]
        guard = ROOT / 'shared/native/app/Privacy/InferencePrivacy.c'
        objects = []
        if guard.exists():
            obj = Path(directory) / 'guard.o'
            subprocess.run(flags + (['-Dsetenv=blocked_setenv'] if fail else []) +
                           ['-c', str(guard), '-o', str(obj)], check=True, capture_output=True)
            objects.append(str(obj))
        probe = Path(directory) / 'probe'
        subprocess.run(flags + [str(ROOT / s) for s in sources] + objects +
                       ['-Wl,-dead_strip', '-Wl,-undefined,dynamic_lookup', '-o', str(probe)],
                       check=True, capture_output=True)
        return probe

    def test_every_entry_disables_telemetry_before_sdk_even_if_environment_enables_it(self):
        with tempfile.TemporaryDirectory() as d:
            probe = self.build_probe(d)
            for entry in range(6):
                for initial in (None, '0'):
                    with self.subTest(entry=entry, initial=initial):
                        env = dict(os.environ)
                        env.pop('ORT_DISABLE_TELEMETRY', None)
                        if initial is not None:
                            env['ORT_DISABLE_TELEMETRY'] = initial
                        result = subprocess.run([str(probe), str(entry), '2'], env=env, capture_output=True, text=True)
                        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failed_opt_out_never_enters_sdk(self):
        with tempfile.TemporaryDirectory() as d:
            probe = self.build_probe(d, fail=True)
            for entry in range(6):
                with self.subTest(entry=entry):
                    result = subprocess.run([str(probe), str(entry), '0'],
                                            env=dict(os.environ, ORT_DISABLE_TELEMETRY='0'), capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
