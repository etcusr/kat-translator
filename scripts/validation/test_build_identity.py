"""Behavioral checks for the diagnostic source/build fingerprint."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'build-identity.py'

class BuildIdentityTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('build_identity', SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.put('shared/apple/Screen.swift', 'let title = "Kat"')
        self.put('assets/bundled/icon.txt', 'icon A')
        self.put('apps/macos/Main.swift', 'mac app')
        self.put('shared/packages/OfflineCore/Sources/Core.swift', 'shared core')
        self.put('shared/packages/OfflineCore/Package.swift', 'manifest')
        self.put('Dependencies/runtime.lock.json', '{"version":1}')
        self.put('apps/ios/OfflineTranslator.xcodeproj/project.pbxproj', 'ios project')
        self.put('apps/macos/KatTranslatorMac.xcodeproj/project.pbxproj', 'mac project')
    def put(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    def identity(self, platform='macosx', configuration='Release'):
        return self.module.build_identity(self.root, platform, {'CONFIGURATION': configuration, 'ARCHS': 'arm64'})
    def test_stable_across_location_and_timestamps(self):
        first = self.identity()
        (self.root/'shared/apple/Screen.swift').touch()
        self.assertEqual(first, self.identity())
        with tempfile.TemporaryDirectory() as other:
            import shutil
            shutil.copytree(self.root, Path(other)/'checkout')
            self.assertEqual(first, self.module.build_identity(Path(other)/'checkout', 'macosx', {'CONFIGURATION':'Release','ARCHS':'arm64'}))
    def test_same_size_edit_changes_id(self):
        first = self.identity()
        self.put('shared/apple/Screen.swift', 'let title = "Cat"')
        self.assertNotEqual(first['identifier'], self.identity()['identifier'])
    def test_resources_dependencies_and_configuration_change_id(self):
        before = self.identity()
        self.put('assets/bundled/icon.txt', 'icon B')
        self.assertNotEqual(before['identifier'], self.identity()['identifier'])
        before = self.identity()
        self.put('Dependencies/runtime.lock.json', '{"version":2}')
        self.assertNotEqual(before['identifier'], self.identity()['identifier'])
        self.assertNotEqual(self.identity()['identifier'], self.identity(configuration='Debug')['identifier'])
        self.assertNotEqual(self.identity()['identifier'], self.identity('iphoneos')['identifier'])
    def test_models_history_tests_and_signing_credentials_do_not_affect_id(self):
        before = self.identity()
        for path in ['model-store/downloads/model.bin', '.build/output', 'apps/ios/Config/Signing.local.xcconfig', 'Tests/test.swift', 'docs/notes.md', 'shared/packages/OfflineCore/.build/module.o', 'shared/apple/.DS_Store']:
            self.put(path, 'ignored local material')
        self.assertEqual(before, self.identity())
    def test_platform_specific_sources(self):
        ios = self.identity('iphoneos'); mac = self.identity()
        self.put('apps/macos/Main.swift', 'changed mac app')
        self.assertEqual(ios, self.identity('iphoneos'))
        self.assertNotEqual(mac, self.identity())
    def test_writes_valid_plist_without_self_hash_or_timestamp(self):
        identity = self.identity()
        output = self.root/'.build/BuildIdentity.plist'
        self.module.write_identity(output, identity)
        import plistlib
        self.assertEqual(plistlib.loads(output.read_bytes()), identity)
        stamp = output.stat().st_mtime_ns
        self.module.write_identity(output, identity)
        self.assertEqual(stamp, output.stat().st_mtime_ns)
        self.assertEqual(identity, self.identity())
        self.assertRegex(identity['identifier'], r'^mac-[0-9a-f]{16}$')
        self.assertEqual(len(identity['sha256']), 64)

if __name__ == '__main__': unittest.main()
