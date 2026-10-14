#!/usr/bin/env python3
"""Offline source-contract and ARM64 APK packaging audit, not an inference test.

No downloads, extraction, SDK installation, device changes or model copies.
Exit 0 means only the requested static checks passed; exit 1 means a check failed.
"""
import argparse
import json
from pathlib import Path
import re
import struct
from urllib.parse import urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def check_files(records, require_url=False):
    errors, paths = [], set()
    if not records:
        return ["empty package"]
    for row in records:
        path = row.get("path", "")
        if (not isinstance(path, str) or not path or "\\" in path or ":" in path
                or any(ord(c) < 32 for c in path)
                or any(p in ("", ".", "..") for p in path.split("/"))):
            errors.append(f"unsafe path: {path!r}")
        if isinstance(path, str):
            if path in paths:
                errors.append(f"duplicate path: {path}")
            paths.add(path)
        size = row.get("byteCount")
        if type(size) is not int or size <= 0:
            errors.append(f"invalid size: {path}")
        if not re.fullmatch(r"[0-9a-f]{64}", str(row.get("sha256", ""))):
            errors.append(f"invalid SHA-256: {path}")
        if require_url:
            try:
                url = urlsplit(row.get("remoteURL", ""))
                valid = url.scheme == "https" and url.hostname and not url.username and not url.password
            except (TypeError, ValueError):
                valid = False
            if not valid:
                errors.append(f"invalid download URL: {path}")
    return errors


def read_descriptor(path, symbol):
    source = path.read_text()
    match = re.search(r"static let " + re.escape(symbol) + r"\s*=\s*ModelDescriptor\((.*?)(?=\n\s*(?:public )?static let|\n\})",
                      source, re.S)
    if not match:
        raise ValueError(f"missing descriptor: {symbol}")
    fields = {}
    for key, pattern in {
        "remoteURL": r'remoteURL:\s*URL\(string:\s*"([^"]+)"',
        "byteCount": r"byteCount:\s*([0-9_]+)",
        "sha256": r'sha256:\s*"([a-f0-9]{64})"',
    }.items():
        value = re.search(pattern, match[1])
        if not value:
            raise ValueError(f"unrecognized {symbol}.{key}; update the source adapter")
        fields[key] = int(value[1].replace("_", "")) if key == "byteCount" else value[1]
    return fields


def check_repository(root):
    errors = []
    report = {"default_translation": "opus-mt-big-en-zle-int8",
              "primary_translation": "index-translate-9b-q4km",
              "android_inference_verified": False, "verified_manifest_entries": 0}
    try:
        contract = json.loads((root / "docs/android/portability-contract.json").read_text())
        if contract["primary_translation"] != report["primary_translation"]:
            errors.append("primary translation must remain Index 9B")
        if contract.get("default_translation") != report["default_translation"]:
            errors.append("Android default translation must be validated OPUS Big")
        for model in contract["models"]:
            actual = read_descriptor(root / model["source"], model["symbol"])
            if actual != model["asset"]:
                errors.append(f"source model changed: {model['symbol']}; review Android contract")
            errors += check_files([{**actual, "path": model["symbol"]}], require_url=True)
        for pin in contract["runtime_pins"]:
            value = json.loads((root / pin["source"]).read_text())
            for key in pin["key"]:
                value = value[key]
            if value != pin["commit"]:
                errors.append(f"runtime pin changed: {pin['name']}")
        for name, key, require_url in [
            ("voice-manifests.json", "files", False),
            ("additional-voices.json", "parts", True),
            ("recognition-packages.json", "parts", True),
        ]:
            packages = json.loads((root / "assets/catalogs" / name).read_text())
            ids = [p["id"] for p in packages]
            if len(ids) != len(set(ids)):
                errors.append(f"duplicate package IDs in {name}")
            for package in packages:
                files = package[key]
                errors.extend(f"{name}/{package['id']}: {e}"
                              for e in check_files(files, require_url=require_url))
                report["verified_manifest_entries"] += len(files)
        files = json.loads((root / "assets/catalogs/opus-package.json").read_text())
        errors.extend(check_files(files, require_url=True))
        report["verified_manifest_entries"] += len(files)
        report["opus_download_bytes"] = sum(f["byteCount"] for f in files)
        recognition = json.loads((root / "assets/catalogs/recognition-packages.json").read_text())
        report["apple_only_packages"] = [p["id"] for p in recognition
            if any(".mlmodelc/" in f["path"] for f in p["parts"])]
        report["index_download_bytes"] = contract["models"][0]["asset"]["byteCount"]
    except (OSError, ValueError, KeyError, TypeError) as error:
        errors.append(f"incomplete or invalid source tree: {error}")
    return errors, report


def check_elf(stream):
    """Inspect ELF64 little-endian AArch64 PT_LOAD alignment without loading weights."""
    errors = []
    header = stream.read(64)
    if len(header) != 64 or header[:7] != b"\x7fELF\x02\x01\x01":
        return ["not an ELF64 little-endian binary"]
    fields = struct.unpack("<16sHHIQQQIHHHHHH", header)
    if fields[1] != 3 or fields[2] != 183:
        errors.append("not an AArch64 shared object")
    phoff, phsize, count = fields[5], fields[9], fields[10]
    if phsize != 56 or not 1 <= count <= 4096 or not 64 <= phoff <= 1024 * 1024:
        return errors + ["invalid or missing ELF program headers"]
    stream.seek(phoff)
    loads = 0
    for _ in range(count):
        raw = stream.read(phsize)
        if len(raw) != phsize:
            return errors + ["truncated ELF program header"]
        kind, _, offset, address, _, _, _, alignment = struct.unpack("<IIQQQQQQ", raw)
        if kind == 1:
            loads += 1
            if alignment < 16384 or alignment & (alignment - 1):
                errors.append("PT_LOAD alignment is not a power of two >= 16 KiB")
            elif offset % alignment != address % alignment:
                errors.append("PT_LOAD offset/address incongruent")
    if not loads:
        errors.append("no PT_LOAD segments")
    return errors


def audit_apk(path):
    """Strict uncompressed ARM64 release packaging policy; not signature/DEX validation."""
    errors = []
    try:
        with zipfile.ZipFile(path) as archive, path.open("rb") as raw:
            names = archive.namelist()
            if len(names) != len(set(names)):
                errors.append("duplicate ZIP entries")
            for required in ["AndroidManifest.xml", "classes.dex"]:
                if required not in names:
                    errors.append(f"missing {required}")
            libraries = [i for i in archive.infolist() if i.filename.startswith("lib/") and i.filename.endswith(".so")]
            if not libraries:
                errors.append("no native libraries; this is not the Kat native build")
            for entry in libraries:
                if not re.fullmatch(r"lib/arm64-v8a/[^/]+\.so", entry.filename):
                    errors.append(f"unexpected ABI/path: {entry.filename}")
                if entry.compress_type != zipfile.ZIP_STORED:
                    errors.append(f"expected uncompressed native library: {entry.filename}")
                    continue
                raw.seek(entry.header_offset)
                local = raw.read(30)
                if len(local) != 30 or local[:4] != b"PK\x03\x04":
                    errors.append(f"invalid ZIP local header: {entry.filename}")
                    continue
                name_size, extra_size = struct.unpack_from("<HH", local, 26)
                if (entry.header_offset + 30 + name_size + extra_size) % 16384:
                    errors.append(f"ZIP data not 16 KiB aligned: {entry.filename}")
                with archive.open(entry) as binary:
                    errors.extend(f"{entry.filename}: {e}" for e in check_elf(binary))
    except (OSError, ValueError, zipfile.BadZipFile, RuntimeError, EOFError) as error:
        errors.append(f"unreadable APK: {error}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--apk", type=Path, help="also inspect an existing ARM64 APK")
    args = parser.parse_args()
    errors, report = check_repository(args.root)
    report["source_contracts"] = "FAIL" if errors else "PASS"
    report["apk_packaging"] = "NOT_RUN"
    if args.apk:
        apk_errors = audit_apk(args.apk)
        errors += apk_errors
        report["apk_packaging"] = "FAIL" if apk_errors else "PASS_STATIC_ONLY"
    report["errors"] = errors
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
