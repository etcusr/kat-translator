"""Packaging must fail closed and sign frameworks after copying manifests."""
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('privacy_packaging', ROOT / 'scripts/install-ios-privacy-manifests.py')


class PrivacyPackagingTests(unittest.TestCase):
    def setUp(self):
        self.module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Test.app'
        for name in self.module.FRAMEWORKS:
            bundle = self.app / 'Frameworks' / (name + '.framework')
            bundle.mkdir(parents=True)
            (bundle / name).write_bytes(b'unchanged binary')
            (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': name}))

    def test_install_before_sign_and_preserve_binaries(self):
        def sign(command, **kwargs):
            bundle = Path(command[-1])
            self.assertTrue((bundle / 'PrivacyInfo.xcprivacy').is_file())
            self.assertEqual((bundle / bundle.stem).read_bytes(), b'unchanged binary')
            self.assertIn('test-identity', command)
        runner = Mock(side_effect=sign)
        self.module.install(self.app, identity='test-identity', runner=runner)
        self.assertEqual(runner.call_count, 4)

    def test_unsigned_and_repeat_install(self):
        runner = Mock()
        self.module.install(self.app, identity=None, runner=runner)
        first = {p: p.read_bytes() for p in self.app.rglob('PrivacyInfo.xcprivacy')}
        self.module.install(self.app, identity=None, runner=runner)
        self.assertEqual(first, {p: p.read_bytes() for p in first})
        runner.assert_not_called()

    def test_own_framework_minimum_ios_is_set_before_signing(self):
        def sign(command, **kwargs):
            bundle = Path(command[-1])
            if bundle.stem in ('OpusRuntime', 'OmniVoiceRuntime'):
                info = plistlib.loads((bundle / 'Info.plist').read_bytes())
                self.assertEqual(info['MinimumOSVersion'], '18.0')
        self.module.install(self.app, identity='test-identity', runner=sign)

    def test_existing_higher_framework_minimum_is_preserved(self):
        p = self.app / 'Frameworks/OpusRuntime.framework/Info.plist'
        p.write_bytes(plistlib.dumps({'CFBundleExecutable': 'OpusRuntime', 'MinimumOSVersion': '19.0'}))
        self.module.install(self.app, identity=None)
        self.assertEqual(plistlib.loads(p.read_bytes())['MinimumOSVersion'], '19.0')

    def test_missing_framework_fails_before_mutation(self):
        (self.app / 'Frameworks/OmniVoiceRuntime.framework/OmniVoiceRuntime').unlink()
        with self.assertRaises(RuntimeError):
            self.module.install(self.app, identity=None)
        self.assertEqual(list(self.app.rglob('PrivacyInfo.xcprivacy')), [])

    def test_conflicting_upstream_manifest_is_not_overwritten(self):
        p = self.app / 'Frameworks/OmniVoiceRuntime.framework/PrivacyInfo.xcprivacy'
        p.write_bytes(plistlib.dumps({'NSPrivacyTracking': True}))
        with self.assertRaises(RuntimeError):
            self.module.install(self.app, identity=None)
        self.assertTrue(plistlib.loads(p.read_bytes())['NSPrivacyTracking'])
        self.assertEqual(len(list(self.app.rglob('PrivacyInfo.xcprivacy'))), 1)

    def test_source_declarations_are_specific(self):
        self.module.install(self.app, identity=None)
        for name in self.module.FRAMEWORKS:
            data = plistlib.loads((self.app / 'Frameworks' / (name + '.framework') / 'PrivacyInfo.xcprivacy').read_bytes())
            self.assertFalse(data['NSPrivacyTracking'])
            self.assertEqual(data['NSPrivacyCollectedDataTypes'], [])
            reasons = {entry['NSPrivacyAccessedAPIType']: entry['NSPrivacyAccessedAPITypeReasons'] for entry in data['NSPrivacyAccessedAPITypes']}
            expected = {} if name == 'OpusRuntime' else {'NSPrivacyAccessedAPICategoryFileTimestamp': ['C617.1']}
            if name == 'Python':
                expected['NSPrivacyAccessedAPICategorySystemBootTime'] = ['35F9.1']
            self.assertEqual(reasons, expected)

    def test_project_runs_packaging_after_embedding(self):
        project = ROOT / 'apps/ios/OfflineTranslator.xcodeproj/project.pbxproj'
        objects = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project)]))['objects']
        target = next(x for x in objects.values() if x.get('isa') == 'PBXNativeTarget' and x.get('name') == 'OfflineTranslator')
        phases = [objects[key] for key in target['buildPhases']]
        names = [x.get('name') for x in phases]
        privacy = names.index('Install framework privacy manifests')
        self.assertGreater(privacy, names.index('Embed Frameworks'))
        self.assertGreater(privacy, names.index('Bundle offline Thai frontend'))
        self.assertIn('install-ios-privacy-manifests.py', phases[privacy]['shellScript'])

    def test_first_installer_failure_stops_shell_phase(self):
        project = ROOT / 'apps/ios/OfflineTranslator.xcodeproj/project.pbxproj'
        objects = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project)]))['objects']
        script = next(x['shellScript'] for x in objects.values() if x.get('name') == 'Install framework privacy manifests')
        executable = Path(self.temp.name) / 'python3'
        marker = Path(self.temp.name) / 'second-installer'
        executable.write_text('#!/bin/bash\ncase "$1" in *install-ios-privacy-manifests.py) exit 42;; esac\ntouch "$MARKER"\n')
        executable.chmod(0o755)
        result = subprocess.run(['/bin/bash', '-c', script], env=dict(os.environ,
            PATH=str(executable.parent) + ':' + os.environ['PATH'], MARKER=str(marker),
            KAT_REPO_ROOT=str(ROOT), TARGET_BUILD_DIR=str(self.app.parent), WRAPPER_NAME=self.app.name))
        self.assertEqual(result.returncode, 42)
        self.assertFalse(marker.exists())

    def test_signing_failure_stops_build(self):
        with self.assertRaises(RuntimeError):
            self.module.install(self.app, identity='test-identity', runner=Mock(side_effect=RuntimeError('signing failed')))


if __name__ == '__main__':
    unittest.main()
