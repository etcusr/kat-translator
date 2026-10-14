"""Host-side contract/artifact checks. These do not execute Android inference."""
import copy
import io
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
import zipfile

from android_readiness import (
    audit_apk, check_elf, check_files, check_repository, read_descriptor,
)

ROOT = Path(__file__).resolve().parents[2]


def elf(machine=183, alignment=16384, offset=0, address=0, loads=1):
    ident = b"\x7fELF\x02\x01\x01" + bytes(9)
    header = struct.pack("<16sHHIQQQIHHHHHH", ident, 3, machine, 1,
                         0, 64, 0, 0, 64, 56, loads, 0, 0, 0)
    segment = struct.pack("<IIQQQQQQ", 1, 5, offset, address, 0, 0, 0, alignment)
    return header + segment * loads


class ManifestValidation(unittest.TestCase):
    def setUp(self):
        self.record = {"path": "model/model.onnx", "byteCount": 10,
                       "sha256": "a" * 64, "remoteURL": "https://example.org/model"}

    def test_valid_download(self):
        self.assertEqual(check_files([self.record], require_url=True), [])

    def test_bad_paths(self):
        for path in ["../model", "/model", "a/../b", "a//b", "a/./b",
                     "a\\b", "C:/model", "", "a\x00b"]:
            with self.subTest(path=path):
                self.assertTrue(check_files([{**self.record, "path": path}]))

    def test_duplicate_paths(self):
        self.assertTrue(check_files([self.record, self.record]))

    def test_invalid_sizes(self):
        for size in [-1, 0, True, 1.5, "10"]:
            with self.subTest(size=size):
                self.assertTrue(check_files([{**self.record, "byteCount": size}]))

    def test_invalid_digests(self):
        for digest in ["a" * 63, "g" * 64, None]:
            self.assertTrue(check_files([{**self.record, "sha256": digest}]))

    def test_non_https_and_credentials_rejected(self):
        for url in ["http://example.org/a", "file:///tmp/a", "https://",
                    "https://user:password@example.org/a"]:
            self.assertTrue(check_files([{**self.record, "remoteURL": url}], require_url=True))

    def test_url_required_for_download(self):
        row = copy.copy(self.record)
        del row["remoteURL"]
        self.assertTrue(check_files([row], require_url=True))
        self.assertEqual(check_files([row]), [])

    def test_empty_package_rejected(self):
        self.assertTrue(check_files([]))


class SourceContracts(unittest.TestCase):
    def copy_contract_tree(self, root):
        paths = ["docs/android/portability-contract.json", "shared/packages/OfflineCore/Sources/OfflineCore/SharedModelAssets.swift",
                 "shared/packages/OfflineCore/Sources/OfflineCore/ModelStore.swift",
                 "Dependencies/runtime.lock.json", "Dependencies/whisper.lock.json"]
        paths += ["assets/catalogs/" + name + ".json" for name in
                  ["voice-manifests", "additional-voices", "recognition-packages", "opus-package"]]
        for name in paths:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def test_live_repository_contracts(self):
        errors, report = check_repository(ROOT)
        self.assertEqual(errors, [])
        self.assertGreater(report["verified_manifest_entries"], 7000)
        self.assertEqual(report["primary_translation"], "index-translate-9b-q4km")
        self.assertFalse(report["android_inference_verified"])
        self.assertEqual(report["default_translation"], "opus-mt-big-en-zle-int8")

    def test_descriptor_parser_reads_pinned_index(self):
        value = read_descriptor(ROOT / "shared/packages/OfflineCore/Sources/OfflineCore/SharedModelAssets.swift", "indexTranslation")
        self.assertEqual(value["byteCount"], 5780090304)
        self.assertEqual(value["sha256"], "9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713")

    def test_missing_descriptor_fails_closed(self):
        with self.assertRaises(ValueError):
            read_descriptor(ROOT / "shared/packages/OfflineCore/Sources/OfflineCore/SharedModelAssets.swift", "missingModel")

    def test_missing_source_tree_is_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            # A missing source tree must not be reported as a successful audit.
            errors, _ = check_repository(root)
            self.assertTrue(errors)

    def test_changed_primary_model_is_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.copy_contract_tree(root)
            path = root / "docs/android/portability-contract.json"
            data = json.loads(path.read_text())
            data["primary_translation"] = "opus-mt-big-en-zle-int8"
            path.write_text(json.dumps(data))
            errors, _ = check_repository(root)
            self.assertIn("primary translation must remain Index 9B", errors)

    def test_changed_android_default_is_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.copy_contract_tree(root)
            path = root / "docs/android/portability-contract.json"
            data = json.loads(path.read_text())
            data["default_translation"] = "index-translate-9b-q4km"
            path.write_text(json.dumps(data))
            errors, _ = check_repository(root)
            self.assertIn("Android default translation must be validated OPUS Big", errors)

    def test_changed_source_digest_is_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.copy_contract_tree(root)
            path = root / "shared/packages/OfflineCore/Sources/OfflineCore/SharedModelAssets.swift"
            path.write_text(path.read_text().replace(
                "9cc6758b0007f4cbf42ea3400768cbff91ae74ef8d640e467158348426d33713", "b" * 64))
            errors, _ = check_repository(root)
            self.assertTrue(any("source model changed: indexTranslation" in e for e in errors))

    def test_changed_runtime_commit_is_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.copy_contract_tree(root)
            path = root / "Dependencies/runtime.lock.json"
            data = json.loads(path.read_text())
            data["llama"]["commit"] = "b" * 40
            path.write_text(json.dumps(data))
            errors, _ = check_repository(root)
            self.assertIn("runtime pin changed: llama.cpp", errors)


class ElfValidation(unittest.TestCase):
    def test_arm64_16k(self):
        self.assertEqual(check_elf(io.BytesIO(elf())), [])

    def test_64k_is_also_16k_compatible(self):
        self.assertEqual(check_elf(io.BytesIO(elf(alignment=65536))), [])

    def test_reject_4k(self):
        self.assertTrue(check_elf(io.BytesIO(elf(alignment=4096))))

    def test_reject_non_power_of_two_alignment(self):
        self.assertTrue(check_elf(io.BytesIO(elf(alignment=24576))))

    def test_reject_wrong_abi(self):
        self.assertTrue(check_elf(io.BytesIO(elf(machine=62))))

    def test_reject_macho(self):
        self.assertTrue(check_elf(io.BytesIO(b"\xcf\xfa\xed\xfe" + bytes(120))))

    def test_reject_truncated_program_header(self):
        self.assertTrue(check_elf(io.BytesIO(elf()[:-5])))

    def test_reject_no_load_segments(self):
        self.assertTrue(check_elf(io.BytesIO(elf(loads=0))))

    def test_reject_incongruent_mapping(self):
        self.assertTrue(check_elf(io.BytesIO(elf(offset=4096, address=0))))


class ApkValidation(unittest.TestCase):
    def make_apk(self, path, native=True, aligned=True, data=None, abi="arm64-v8a"):
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("AndroidManifest.xml", b"synthetic-test-manifest")
            archive.writestr("classes.dex", b"synthetic-test-dex")
            if native:
                info = zipfile.ZipInfo(f"lib/{abi}/libkat.so")
                if aligned:
                    start = archive.fp.tell() + 30 + len(info.filename.encode())
                    padding = (-start) % 16384
                    if padding < 4:
                        padding += 16384
                    info.extra = struct.pack("<HH", 0xffff, padding - 4) + bytes(padding - 4)
                archive.writestr(info, elf() if data is None else data)

    def test_valid_native_packaging(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.apk"
            self.make_apk(path)
            self.assertEqual(audit_apk(path), [])

    def test_unaligned_zip_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.apk"
            self.make_apk(path, aligned=False)
            self.assertTrue(audit_apk(path))

    def test_empty_shell_is_not_a_native_build(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.apk"
            self.make_apk(path, native=False)
            self.assertTrue(audit_apk(path))

    def test_wrong_binary_inside_correct_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.apk"
            self.make_apk(path, data=elf(machine=62))
            self.assertTrue(audit_apk(path))

    def test_wrong_abi_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.apk"
            self.make_apk(path, abi="x86_64")
            self.assertTrue(audit_apk(path))

    def test_missing_apk_is_failure(self):
        self.assertTrue(audit_apk(Path("/nonexistent/kat-test.apk")))

    def test_non_zip_is_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.apk"
            path.write_bytes(b"not a zip")
            self.assertTrue(audit_apk(path))


if __name__ == "__main__":
    unittest.main()
