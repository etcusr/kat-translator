#!/usr/bin/env python3
"""Resolve one stable direct-Mac identity for Xcode and packaging."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

INSTALLED_APP = Path("/Applications/Kat translator.app")


def available_identities():
    output = subprocess.check_output(
        ["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    return re.findall(r'\) ([0-9A-Fa-f]{40}) "(.*?)"', output)


def installed_certificate(app=INSTALLED_APP):
    if not app.exists():
        return None
    # Do not replace an unreadable/broken signature with a different identity.
    result = subprocess.run(["codesign", "-dv", str(app)], capture_output=True,
                            text=True, check=True)
    if "Signature=adhoc" in result.stderr:
        return None
    with tempfile.TemporaryDirectory(prefix="kat-signing-") as directory:
        prefix = str(Path(directory) / "certificate")
        subprocess.run(["codesign", "-d", "--extract-certificates=" + prefix, str(app)],
                       capture_output=True, check=True)
        leaf = Path(prefix + "0")
        if not leaf.exists():
            raise RuntimeError("Cannot read installed Kat signing certificate")
        return hashlib.sha1(leaf.read_bytes()).hexdigest().upper()


def choose_identity(identities, installed=None, explicit=None):
    identities = [(fingerprint.upper(), name) for fingerprint, name in identities]
    if explicit:
        # Fingerprints are safe xcconfig values; codesign/Xcode validates the key.
        if explicit == "-" or re.fullmatch(r"[0-9a-fA-F]{40}", explicit):
            return explicit.upper()
        matches = [fingerprint for fingerprint, name in identities if name == explicit]
        if len(matches) == 1:
            return matches[0]
        raise RuntimeError("KAT_MAC_SIGNING_IDENTITY must identify one available certificate")
    if installed:
        if installed.upper() in {fingerprint for fingerprint, _ in identities}:
            return installed.upper()
        raise RuntimeError("Installed Kat signing key is unavailable; restore it or explicitly "
                           "set KAT_MAC_SIGNING_IDENTITY to migrate the identity")
    for prefix in ("Developer ID Application:", "Apple Development:"):
        matches = [fingerprint for fingerprint, name in identities if name.startswith(prefix)]
        if len(matches) == 1:
            return matches[0]
        if matches:
            raise RuntimeError("Multiple signing certificates: set KAT_MAC_SIGNING_IDENTITY explicitly")
    raise RuntimeError("No signing certificate available; no automatic ad-hoc fallback. "
                       "Use KAT_MAC_SIGNING_IDENTITY=- only for disposable builds")


def resolve_identity():
    explicit = os.environ.get("KAT_MAC_SIGNING_IDENTITY", "").strip()
    if explicit == "-" or re.fullmatch(r"[0-9a-fA-F]{40}", explicit):
        return choose_identity([], explicit=explicit)
    return choose_identity(available_identities(),
                           installed_certificate() if not explicit else None, explicit)


if __name__ == "__main__":
    try:
        print(resolve_identity())
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
