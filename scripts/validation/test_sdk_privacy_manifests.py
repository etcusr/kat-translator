"""Fail closed if a repackaged SDK disappears or brings a changed disclosure."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]


class SDKPrivacyTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('sdk_privacy', ROOT / 'scripts/install-sdk-privacy-manifests.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Sample.app'
        for name in ('OfflineTranslator', 'FluidAudio_FluidAudio.bundle/Info.plist'):
            p = self.app / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'test.fluid'}) if name.endswith('plist') else b'binary')

    def test_ios_static_sdk_manifests_have_own_bundles_and_repeat_safely(self):
        self.module.install(self.app, 'ios', identity=None)
        manifests = sorted(self.app.rglob('PrivacyInfo.xcprivacy'))
        self.assertEqual(len(manifests), 3)
        for name in ('ONNXRuntimePrivacy', 'SherpaOnnxPrivacy'):
            bundle = self.app / (name + '.bundle')
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            self.assertNotIn('CFBundleExecutable', info)
            self.assertNotEqual(info['CFBundleIdentifier'], 'app.kattranslator')
            data = plistlib.loads((bundle / 'PrivacyInfo.xcprivacy').read_bytes())
            self.assertFalse(data['NSPrivacyTracking'])
            self.assertEqual(data['NSPrivacyAccessedAPITypes'][0]['NSPrivacyAccessedAPITypeReasons'], ['C617.1'])
        first = {p: p.read_bytes() for p in self.app.rglob('*') if p.is_file()}
        self.module.install(self.app, 'ios', identity=None)
        self.assertEqual(first, {p: p.read_bytes() for p in self.app.rglob('*') if p.is_file()})

    def test_missing_sdk_and_changed_upstream_stop_before_writes(self):
        (self.app / 'OfflineTranslator').unlink()
        with self.assertRaises(RuntimeError):
            self.module.install(self.app, 'ios', identity=None)
        self.assertEqual(list(self.app.rglob('PrivacyInfo.xcprivacy')), [])
        (self.app / 'OfflineTranslator').write_bytes(b'binary')
        target = self.app / 'FluidAudio_FluidAudio.bundle/PrivacyInfo.xcprivacy'
        target.write_bytes(plistlib.dumps({'NSPrivacyTracking': True}))
        with self.assertRaises(RuntimeError):
            self.module.install(self.app, 'ios', identity=None)
        self.assertEqual(list(self.app.rglob('PrivacyInfo.xcprivacy')), [target])
        self.assertTrue(plistlib.loads(target.read_bytes())['NSPrivacyTracking'])

    def test_mac_layout_and_signing_after_manifest(self):
        paths = ['Contents/MacOS/Kat translator', 'Contents/Frameworks/libonnxruntime.dylib',
                 'Contents/Frameworks/libsherpa-onnx-c-api.dylib',
                 'Contents/Frameworks/OpusRuntime.framework/Versions/A/OpusRuntime',
                 'Contents/Resources/IndexPython/google/_upb/_message.abi3.so',
                 'Contents/Resources/IndexPython/sentencepiece/_sentencepiece.test.so',
                 'Contents/Resources/OpusPython/sentencepiece/_sentencepiece.test.so',
                 'Contents/Resources/OpusPython/torch/lib/libtorch_cpu.dylib',
                 'Contents/Resources/FluidAudio_FluidAudio.bundle/Contents/Info.plist']
        for name in paths:
            p = self.app / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(b'binary')
        fluid = self.app / 'Contents/Resources/FluidAudio_FluidAudio.bundle/Contents'
        (fluid / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'test.fluid'}))
        signature = fluid / '_CodeSignature'
        signature.mkdir()
        (signature / 'CodeResources').write_bytes(b'stale seal from normal Mac build')
        def sign(command, **kwargs):
            bundle = Path(command[-1])
            self.assertTrue((bundle / 'Versions/A/Resources/PrivacyInfo.xcprivacy').exists())
        runner = Mock(side_effect=sign)
        self.module.install(self.app, 'macos', identity='test', runner=runner)
        self.assertEqual(runner.call_count, 1)
        self.assertFalse(signature.exists(), 'Adding a resource must not leave a stale bundle signature')
        self.assertEqual(len(list(self.app.rglob('PrivacyInfo.xcprivacy'))), 8)
        for p in self.app.rglob('PrivacyInfo.xcprivacy'):
            data = plistlib.loads(p.read_bytes())
            self.assertEqual(data['NSPrivacyAccessedAPITypes'], [])
            self.assertEqual(data['NSPrivacyCollectedDataTypes'], [])
        runner.side_effect = RuntimeError('signing failed')
        with self.assertRaises(RuntimeError):
            self.module.install(self.app, 'macos', identity='test', runner=runner)


if __name__ == '__main__':
    unittest.main()
