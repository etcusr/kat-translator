"""Static typography checks: original and translation text on one screen use the same style.

SwiftUI fonts are not inspectable from XCUITest, so the views are checked in source:
every content view must set an explicit shared AppPlatform font, and all content views of
one screen must use the same one (iOS once showed the Voice original in .body and the
translation in .title3).
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APPLE = ROOT / "shared/apple"
ANDROID = ROOT / "apps/android/app/src/main/java"
CONTENT_ID = re.compile(r'"(\w+)\.(?:original|translation|source|target)\.text"')
# Screens whose every font comes from AppPlatform; extend as other screens are cleaned up.
PANEL_SCREENS = ["Models/LanguageSetupView.swift", "Models/OpusDirectionsView.swift"]
FONT = re.compile(r"\.font\((AppPlatform\.\w+)\)")


def chain(lines, index):
    """The modifier chain (one SwiftUI view expression) that contains line `index`."""
    start = index
    while start > 0 and lines[start].lstrip().startswith("."):
        start -= 1
    end = index
    while end + 1 < len(lines) and lines[end + 1].lstrip().startswith("."):
        end += 1
    return start, "\n".join(lines[start:end + 1])


def apple_content_views():
    """(screen, file:line, chain) for each original/translation view in the shared Apple UI."""
    views = []
    for path in sorted(APPLE.rglob("*.swift")):
        if "/tests/" in path.as_posix():
            continue
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            match = CONTENT_ID.search(line)
            # The Text screen's editable original has no identifier (UI tests find it by label).
            editor = path.name == "TextTranslationFields.swift" and "TextEditor(text: editable)" in line
            if not (match or editor) or line.lstrip().startswith("//"):
                continue
            start, body = chain(lines, i)
            views.append((match.group(1) if match else "text", f"{path.relative_to(ROOT)}:{start + 1}", body))
    return views


class UITypographyTests(unittest.TestCase):
    def test_apple_content_views_found(self):
        screens = {screen for screen, _, _ in apple_content_views()}
        self.assertTrue({"voice", "text"} <= screens, screens)

    def test_apple_original_and_translation_share_one_font(self):
        fonts = {}
        for screen, where, body in apple_content_views():
            found = FONT.findall(body)
            self.assertEqual(len(found), 1, f"{where}: content text needs exactly one .font(AppPlatform.…)\n{body}")
            fonts.setdefault(screen, {})[where] = found[0]
        for screen, by_view in fonts.items():
            self.assertEqual(len(set(by_view.values())), 1, f"{screen}: different fonts {by_view}")

    def test_panel_screens_use_only_shared_fonts(self):
        # Mixed .caption/.headline and system defaults made the Mac language setup look uneven.
        for name in PANEL_SCREENS:
            for number, line in enumerate((APPLE / name).read_text().splitlines(), 1):
                for font in re.findall(r"\.font\(([^()]*(?:\([^()]*\))?[^()]*)\)", line):
                    self.assertTrue(font.startswith("AppPlatform."), f"{name}:{number}: use an AppPlatform font, not {font}")

    def test_android_original_and_translation_share_one_font(self):
        sizes = {}
        for path in sorted(ANDROID.rglob("*.kt")):
            for number, line in enumerate(path.read_text().splitlines(), 1):
                for tag in re.findall(r'"(\w+)\.(?:original|translation|source|target)\.text"', line):
                    size = re.findall(r"fontSize\s*=\s*([\d.]+)\.sp", line)
                    self.assertTrue(size, f"{path.name}:{number}: content text needs fontSize")
                    sizes.setdefault(tag, set()).update(size)
        self.assertTrue(sizes)
        for tag, values in sizes.items():
            self.assertEqual(len(values), 1, f"{tag}: different font sizes {values}")


if __name__ == "__main__":
    unittest.main()
