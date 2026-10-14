"""Repository ownership checks, including source/resource membership in Apple builds."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RepositoryLayoutTests(unittest.TestCase):
    def test_platform_entrypoints_are_separate(self):
        for name in ["apps/ios/OfflineTranslatorApp.swift", "apps/macos/KatMacApp.swift",
                     "apps/android/README.md", "shared/apple/Conversation/AppModel.swift"]:
            with self.subTest(path=name):
                self.assertTrue((ROOT / name).is_file(), name)

    def test_catalogs_and_voices_have_one_source(self):
        for name in ["voice-manifests.json", "additional-voices.json", "opus-package.json",
                     "recognition-packages.json"]:
            self.assertTrue((ROOT / "assets/catalogs" / name).is_file(), name)
            self.assertFalse(any(p for p in (ROOT / "apps").rglob(name) if not any(v in {"build", ".gradle", ".cxx"} for v in p.parts)), name)
        self.assertTrue((ROOT / "assets/bundled/VoicePreviews").is_dir())

    def test_shipped_voice_previews_are_not_ignored(self):
        previews=list((ROOT/'assets/bundled/VoicePreviews').glob('*.m4a'))+list((ROOT/'assets/bundled/Voices').glob('*.m4a'))
        self.assertGreater(len(previews), 100)
        result=subprocess.run(['git','check-ignore','--stdin'],cwd=ROOT,input='\n'.join(str(p.relative_to(ROOT)) for p in previews),text=True,capture_output=True)
        self.assertEqual(result.returncode,1,result.stdout+result.stderr)

    def test_no_model_weights_in_platform_sources(self):
        for path in (ROOT / "apps").rglob("*"):
            if any(part in {"build", ".gradle", ".cxx"} for part in path.parts):
                continue
            if path.is_file():
                self.assertNotIn(path.suffix, {".gguf", ".onnx", ".ftz", ".spm"}, str(path))

    def test_old_app_source_roots_are_gone(self):
        for folder in ["App", "MacApp", "Shared", "Packages", "Native", "DownloadActivity"]:
            self.assertNotIn(folder, [p.name for p in ROOT.iterdir()])

    def test_apple_project_references_resolve(self):
        for project in ["apps/ios/OfflineTranslator.xcodeproj", "apps/macos/KatTranslatorMac.xcodeproj"]:
            path = ROOT / project / "project.pbxproj"
            self.assertTrue(path.is_file(), project)
            data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
            objects = data["objects"]
            main = objects[objects[data["rootObject"]]["mainGroup"]]
            base = (path.parent.parent / main.get("path", "")).resolve()
            self.assertEqual(base, ROOT)
            def exact_case(path):
                current=ROOT
                for component in path.parts:
                    self.assertIn(component, {p.name for p in current.iterdir()}, str(path))
                    current=current/component
            for entry in objects.values():
                if entry["isa"] == "PBXFileReference" and entry.get("sourceTree") == "<group>" and "path" in entry:
                    self.assertTrue((base / entry["path"]).exists(), entry["path"])
                    exact_case(Path(entry["path"]))
                if entry["isa"] == "XCLocalSwiftPackageReference":
                    self.assertTrue((path.parent.parent / entry["relativePath"]).is_dir(), entry["relativePath"])

    def test_apple_build_membership_preserved(self):
        expected=json.loads((ROOT/'tests/fixtures/apple-build-membership.json').read_text())
        for platform,project in [('ios','OfflineTranslator'),('macos','KatTranslatorMac')]:
            data=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(ROOT/'apps'/platform/(project+'.xcodeproj/project.pbxproj'))]))
            objects=data['objects']
            for target in objects.values():
                if target.get('isa')!='PBXNativeTarget':continue
                for phase_id in target['buildPhases']:
                    phase=objects[phase_id]
                    if phase['isa'] not in ['PBXSourcesBuildPhase','PBXResourcesBuildPhase']:continue
                    actual=[objects[objects[f]['fileRef']]['path'] for f in phase['files'] if 'fileRef' in objects[f]]
                    # Snapshot of generated membership; regenerate the fixture only for an intentional change.
                    old=expected[platform][target['name']][phase['isa']]
                    self.assertEqual(sorted(actual),sorted(old))

    def test_latest_release_fixes_preserved(self):
        # The migration must preserve the latest source, not the earlier planning snapshot.
        voice = (ROOT / "shared/apple/Speech/VoiceSettingsView.swift").read_text()
        self.assertIn('language.rawValue + "." + $0.model.id', voice)
        import plistlib
        ios = plistlib.loads((ROOT / "apps/ios/Info.plist").read_bytes())
        mac = plistlib.loads((ROOT / "apps/macos/Info.plist").read_bytes())
        # Later releases may advance independently; reject a migration downgrade.
        for info, version, build in [(ios, (0, 5, 3), 32), (mac, (0, 5, 4), 52)]:
            self.assertGreaterEqual(tuple(map(int, info["CFBundleShortVersionString"].split("."))), version)
            self.assertGreaterEqual(int(info["CFBundleVersion"]), build)


if __name__ == "__main__":
    unittest.main()
