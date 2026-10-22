"""Signing selection and generated direct-project integration contracts."""
import contextlib
import io
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
CERT = "A" * 40
OTHER = "B" * 40


class IdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.signing = runpy.run_path(str(ROOT / "scripts/mac-signing.py"))

    def choose(self, *args, **kwargs):
        return self.signing["choose_identity"](*args, **kwargs)

    def test_installed_certificate_wins_over_new_certificate_types(self):
        self.assertEqual(self.choose([(CERT, "Apple Development: Existing"),
                                      (OTHER, "Developer ID Application: New")], CERT), CERT)

    def test_missing_installed_key_does_not_migrate_silently(self):
        with self.assertRaisesRegex(RuntimeError, "Installed Kat signing key"):
            self.choose([(OTHER, "Apple Development: New")], CERT)

    def test_fresh_machine_prefers_unique_developer_id(self):
        self.assertEqual(self.choose([(CERT, "Apple Development: Dev"),
                                      (OTHER, "Developer ID Application: Release")]), OTHER)

    def test_no_key_or_ambiguous_keys_fail(self):
        for rows in ([], [(CERT, "Apple Development: First"),
                          (OTHER, "Apple Development: Second")]):
            with self.subTest(rows=rows), self.assertRaises(RuntimeError):
                self.choose(rows)

    def test_explicit_disposable_adhoc_and_certificate_override(self):
        self.assertEqual(self.choose([], explicit="-"), "-")
        self.assertEqual(self.choose([], CERT, OTHER.lower()), OTHER)
        self.assertEqual(self.choose([(CERT, "Apple Development: Dev")],
                                     explicit="Apple Development: Dev"), CERT)

    def test_unknown_name_and_config_injection_fail(self):
        for value in ("Missing", "A\nCODE_SIGN_IDENTITY = -"):
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                self.choose([], explicit=value)


class ProjectSigningTests(unittest.TestCase):
    def test_mac_sources_exclude_ios_background_task_and_keep_shared_downloads(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".build", prefix="mac-sources-test-") as folder:
            with patch.dict(os.environ, {"KAT_MAC_STORE_PROJECT": folder,
                                         "KAT_MAC_STORE_INFOPLIST": "StoreInfo.plist",
                                         "KAT_APPLE_TEAM_ID": "TESTTEAM",
                                         "KAT_MAC_PROFILE": "modern"}), \
                    contextlib.redirect_stdout(io.StringIO()):
                result = runpy.run_path(str(ROOT / "scripts/generate-macos-project.py"))
            phase = result["objects"][result["ns"]["sources"]]
            paths = {result["path_for_build"](key) for key in phase["files"]}
            self.assertNotIn("apps/ios/Models/DownloadContinuedTask.swift", paths)
            self.assertNotIn("apps/ios/Models/DownloadLiveActivity.swift", paths)
            self.assertIn("shared/apple/Models/PackageDownloadCoordinator.swift", paths)
            self.assertIn("shared/apple/Settings/SettingsView.swift", paths)

    def test_store_project_keeps_automatic_signing_without_direct_key(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".build", prefix="signing-store-test-") as folder:
            with patch.dict(os.environ, {"KAT_MAC_STORE_PROJECT": folder,
                    "KAT_MAC_SIGNING_IDENTITY": "not-an-available-certificate",
                    "KAT_MAC_STORE_INFOPLIST": "StoreInfo.plist",
                    "KAT_APPLE_TEAM_ID": "TESTTEAM", "KAT_MAC_PROFILE": "modern"}), \
                    contextlib.redirect_stdout(io.StringIO()):
                result = runpy.run_path(str(ROOT / "scripts/generate-macos-project.py"))
            for name in ("Debug", "Release"):
                config = result["objects"][result["uid"]("target" + name)]
                self.assertEqual(config["buildSettings"]["CODE_SIGN_STYLE"], "Automatic")
                self.assertEqual(config["buildSettings"]["CODE_SIGN_IDENTITY"], "Apple Development")
                self.assertNotIn("baseConfigurationReference", config)

    def test_direct_project_uses_explicit_certificate_without_committing_it(self):
        project = ROOT / "apps/macos/KatTranslatorMac.xcodeproj"
        paths = [project / "project.pbxproj",
                 project / "xcshareddata/xcschemes/KatTranslatorMac.xcscheme",
                 ROOT / ".build/macos-signing.xcconfig"]
        before = {p: p.read_bytes() if p.exists() else None for p in paths}
        try:
            with patch.dict(os.environ, {"KAT_MAC_SIGNING_IDENTITY": CERT,
                                         "KAT_MAC_PROFILE": "modern"}), \
                    contextlib.redirect_stdout(io.StringIO()):
                os.environ.pop("KAT_MAC_STORE_PROJECT", None)
                result = runpy.run_path(str(ROOT / "scripts/generate-macos-project.py"))
            objects, uid = result["objects"], result["uid"]
            for name in ("Debug", "Release"):
                config = objects[uid("target" + name)]
                self.assertEqual(config["buildSettings"]["CODE_SIGN_IDENTITY"],
                                 "$(KAT_MAC_SIGNING_IDENTITY)")
                self.assertIn("baseConfigurationReference", config)
            self.assertIn("KAT_MAC_SIGNING_IDENTITY = " + CERT, paths[2].read_text())
            self.assertNotIn(CERT, paths[0].read_text())
        finally:
            for path, content in before.items():
                if content is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_bytes(content)


if __name__ == "__main__":
    unittest.main()
