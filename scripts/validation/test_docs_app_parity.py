"""In-app descriptions, current documentation and the catalogs must state the same facts.

Each claim is a pattern whose number is compared with a value derived from assets/catalogs
(or from the build files for versions). A claim must match at least once, so a reworded
text fails loudly instead of silently escaping the check; add or adjust the pattern then.
"""
import json
import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = ROOT / "assets/catalogs"
ANDROID = ROOT / "apps/android/app/src/main/java"
DOCS = [ROOT / "docs/CURRENT_STATE.md", ROOT / "docs/ARCHITECTURE.md"]


def facts():
    directions = json.loads((CATALOGS / "opus-direction-packages.json").read_text())
    capabilities = json.loads((CATALOGS / "android-capabilities.json").read_text())
    languages = {lang for d in directions for lang in d["sources"] + d["targets"]}
    english = {t for d in directions if "en" in d["sources"] for t in d["targets"]} | \
              {s for d in directions if "en" in d["targets"] for s in d["sources"]}
    hosted = sum("HOSTING-PENDING" not in d["parts"][0]["remoteURL"] for d in directions)
    return {
        "opus languages": len(languages),
        "opus directions": len(directions),
        "opus hosted": hosted,
        "opus manual": len(directions) - hosted,
        "opus english partners": len(english - {"en"}),
        "index languages": len(capabilities["index"]),
        "ultra languages": len(capabilities["ultra"]),
        "omnilingual languages": len(capabilities["omnilingual"]),
        "supertonic languages": len(capabilities["supertonic"]),
    }


def app_strings():
    """Every user-visible literal: Apple string catalog keys and Android tr(...) literals."""
    strings = list(json.loads((ROOT / "assets/bundled/Localizable.xcstrings").read_text())["strings"])
    for path in ANDROID.rglob("*.kt"):
        strings += re.findall(r'tr\("((?:[^"\\]|\\.)*)"', path.read_text())
    return strings


def app_code():
    """Source that maps models to their language-count strings."""
    return [p.read_text() for p in [ROOT / "shared/apple/Models/ModelsView.swift",
                                    ANDROID / "org/openoffline/translator/android/ProductModels.kt"]]


# (fact, pattern, where): where is "app" (strings), "code" or "docs".
CLAIMS = [
    ("opus languages", r"(\d+) языков через направления OPUS", "app"),
    ("opus english partners", r"английский ↔ ~(\d+) язык", "app"),
    ("opus english partners", r"EN ↔ ~(\d+) язык", "docs"),
    ("opus directions", r"(\d+) OPUS-направлени", "docs"),
    ("opus directions", r"OPUS-MT Big — (\d+) направлени", "docs"),
    ("opus hosted", r"скачиваются (\d+) направлени", "docs"),
    ("opus manual", r"остальные (\d+) — ручная установка", "docs"),
    ("index languages", r"Index[^.\n\"]{0,30}?(\d+) язык", "app"),
    ("index languages", r"^(\d+) языков(?: ·|\.)", "app"),
    ("index languages", r'case \.index9B, \.index2B: return L10n\.text\("(\d+) языков"\)', "code"),
    ("index languages", r'else tr\("(\d+) языков"\)', "code"),
    ("ultra languages", r"Ultra поддерживает (\d+) язык", "app"),
    ("omnilingual languages", r"Omnilingual добавляет голосовой ввод для (\d+) язык", "app"),
    ("supertonic languages", r"Supertonic[^.\n\"]{0,40}?(\d+) язык", "app"),
    ("supertonic languages", r"Общий пакет удалится для (\d+) язык", "app"),
]


class DocsAppParityTests(unittest.TestCase):
    def test_numeric_claims_match_catalogs(self):
        values = facts()
        sources = {"app": app_strings(), "code": app_code(),
                   "docs": [p.read_text() for p in DOCS]}
        for fact, pattern, where in CLAIMS:
            found = [int(n) for text in sources[where] for n in re.findall(pattern, text, re.M)]
            with self.subTest(fact=fact, pattern=pattern):
                self.assertTrue(found, f"no text matches {pattern!r} in {where}; update the claim")
                self.assertEqual(set(found), {values[fact]}, f"{fact}: catalog has {values[fact]}")

    def test_current_state_versions_match_builds(self):
        state = (ROOT / "docs/CURRENT_STATE.md").read_text()
        gradle = (ROOT / "apps/android/app/build.gradle.kts").read_text()
        code, name = re.search(r'versionCode = (\d+); versionName = "([\d.]+)"', gradle).groups()
        self.assertRegex(state, rf"\| Android \| \*\*{re.escape(name)} / code{code}\*\*")
        for platform, row in [("ios", "iPhone"), ("macos", "Mac современный")]:
            info = plistlib.loads((ROOT / f"apps/{platform}/Info.plist").read_bytes())
            expected = f"| {row} | **{info['CFBundleShortVersionString']} / build{info['CFBundleVersion']}**"
            self.assertIn(expected, state)


if __name__ == "__main__":
    unittest.main()
