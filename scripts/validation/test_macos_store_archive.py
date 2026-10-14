"""Exercise the real store script in a disposable checkout with fake build tools."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "archive-macos-appstore.sh"


class ArchiveFailureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(SCRIPT, self.root / "scripts" / SCRIPT.name)
        # Project generation is outside this suite's archive-failure contract.
        (self.root / "scripts/generate-macos-project.py").write_text("pass\n")
        (self.root / "apps/macos").mkdir(parents=True)
        (self.root / "apps/macos/Info.plist").write_bytes(plistlib.dumps({}))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin", KAT_APPLE_TEAM_ID="TEST",
                        KAT_MAC_STORE_VERSION="1.0", KAT_MAC_STORE_BUILD="999")
        self.output = self.root / ".build/macos-appstore/1.0-999"
        self.tool("xcodebuild", '''echo "$*" >> "$TEST_LOG"
if [[ "$*" == *-exportArchive* ]]; then exit 0; fi
while [ "$1" != -archivePath ]; do shift; done
mkdir -p "$2/Products/Applications/Kat translator.app"
echo "partial build output"
exit "${TEST_BUILD_STATUS:-65}"
''')
        self.tool("codesign", 'echo codesign >> "$TEST_LOG"; exit 77\n')
        self.env["TEST_LOG"] = str(self.root / "calls.log")

    def tool(self, name, body):
        p = self.bin / name
        p.write_text("#!/bin/bash\n" + body)
        p.chmod(0o755)

    def run_script(self):
        return subprocess.run(["/bin/bash", str(self.root / "scripts" / SCRIPT.name)],
                              env=self.env, capture_output=True, text=True)

    def calls(self):
        p = Path(self.env["TEST_LOG"])
        return p.read_text() if p.exists() else ""

    def test_failed_archive_never_verifies_or_exports_partial_app(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertNotIn("codesign", self.calls())
        self.assertNotIn("-exportArchive", self.calls())
        self.assertIn("partial build output", (self.output / "archive.log").read_text())

    def test_existing_output_is_preserved_and_never_reused(self):
        self.output.mkdir(parents=True)
        marker = self.output / "archive.log"
        marker.write_text("previous evidence")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), "")
        self.assertEqual(marker.read_text(), "previous evidence")

    def test_success_without_filtered_lines_reaches_verification(self):
        self.env["TEST_BUILD_STATUS"] = "0"
        result = self.run_script()
        self.assertEqual(result.returncode, 77, result.stderr)
        self.assertIn("codesign", self.calls())

    def test_log_write_failure_stops_before_verification(self):
        self.env["TEST_BUILD_STATUS"] = "0"
        self.tool("tee", 'cat >/dev/null; exit 74\n')
        result = self.run_script()
        self.assertEqual(result.returncode, 74, result.stderr)
        self.assertNotIn("codesign", self.calls())

    def test_version_and_build_cannot_escape_output_directory(self):
        for key in ["KAT_MAC_STORE_VERSION", "KAT_MAC_STORE_BUILD"]:
            with self.subTest(key=key):
                self.env[key] = "../../outside"
                self.assertNotEqual(self.run_script().returncode, 0)
                self.assertEqual(self.calls(), "")
                self.env[key] = "1.0" if key.endswith("VERSION") else "999"


if __name__ == "__main__":
    unittest.main()
