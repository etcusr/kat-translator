#!/usr/bin/env python3
"""Collect the App Store Connect upload package into one folder.

Sources stay in Git (docs/publication/2026-10-14) and in the localized screenshot capture
(dist/store/_sources/localized-2026-10-14). Output (ignored dist):
  dist/store/apple/APP-STORE-TEXTS.txt - every text field, grouped by App Store Connect section (plain text)
  dist/store/apple/screenshots/<iPhone|Mac>/<language>/NN-<screen>.png
  dist/store/apple/header-and-search-results/*.png
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COPY = ROOT / "docs/publication/2026-10-14"
SHOTS = ROOT / "dist/store/_sources/localized-2026-10-14"
OUT = ROOT / "dist/store/apple"
LANGS = [("en", "English (U.S.)", "основной язык"), ("ru", "Russian", ""), ("es", "Spanish (Spain)", ""), ("tr", "Turkish", "")]
PLATFORMS = [("ios", "iPhone", "iOS App"), ("macos", "Mac", "macOS App")]
SCREENS = {"1-text": "01-text", "2-voice": "02-voice", "3-models": "03-models", "4-languages": "04-languages"}


def read(path):
    return path.read_text(encoding="utf-8").strip()


def field(title, value, limit=None, unit="символов"):
    size = len(value.encode("utf-8")) if unit == "байт" else len(value)
    note = f"  ({size} / {limit} {unit})" if limit else ""
    return f"--- {title}{note} ---\n{value}\n"


def heading(text, line="="):
    return f"\n{line * 72}\n{text}\n{line * 72}\n"


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    out = []
    out.append("KAT TRANSLATOR — ТЕКСТЫ ДЛЯ APP STORE CONNECT\n")
    out.append("Один файл со всеми полями карточки. Заголовок каждого блока = раздел App Store Connect, "
               "подзаголовок = язык (переключатель языка справа вверху страницы).\nКопировать текст между строкой «--- Поле ---» и следующей такой строкой.\n")
    out.append("Скриншоты лежат рядом: screenshots/iPhone/<язык>/ и screenshots/Mac/<язык>/, порядок загрузки — по номеру в имени файла.\n"
               "Header и Search Results — header-and-search-results/.\n")
    out.append("Собрано скриптом scripts/publication/build-apple-store-package.py из docs/publication/2026-10-14/.\n")
    out.append("СОДЕРЖАНИЕ")
    out.append("1. App Information — общее для iPhone и Mac (Name, Subtitle)\n2. App Privacy — Privacy Policy URL\n"
               "3. iOS App → обновление — по языкам\n4. macOS App → подготовленные тексты — по языкам\n5. App Review Information → Notes\n")

    out.append(heading("1. App Information (общее для iPhone и Mac)"))
    out.append("Раздел General → App Information. Заполняется один раз на каждый язык.\n")
    for code, name, note in LANGS:
        out.append(heading(f"{name} ({code}){' — ' + note if note else ''}", "-"))
        out.append(field("Name", read(COPY / f"ios/{code}/name.txt"), 30))
        out.append(field("Subtitle", read(COPY / f"ios/{code}/subtitle.txt"), 30))

    out.append(heading("2. App Privacy"))
    out.append("Раздел App Privacy → Privacy Policy URL (по языкам ссылка одинаковая).\n\n")
    out.append(field("Privacy Policy URL", read(COPY / "ios/en/privacy_policy_url.txt")))

    for number, (platform, label, section) in enumerate(PLATFORMS, start=3):
        out.append(heading(f"{number}. {section} → тексты карточки ({label})"))
        out.append("Выбрать редактируемую версию соответствующей платформы. Mac-тексты пока только подготовлены: применять после текущего ревью и публикации по BACKLOG. Поля идут в порядке страницы.\n")
        for code, name, note in LANGS:
            base = COPY / f"{platform}/{code}"
            out.append(heading(f"{label} · {name} ({code}){' — ' + note if note else ''}", "-"))
            out.append(f"Скриншоты: screenshots/{label}/{code}/ (4 шт., по порядку номеров).\n")
            out.append(field("Promotional Text", read(base / "promotional_text.txt"), 170))
            out.append(field("Description", read(base / "description.txt"), 4000))
            out.append(field("Keywords", read(base / "keywords.txt"), 100, "байт"))
            out.append(field("Support URL", read(base / "support_url.txt")))
            out.append(field("Marketing URL", read(base / "marketing_url.txt")))
            out.append(field("What's New (для обновлений)", read(base / "whats-new.txt"), 4000))

    out.append(heading("5. App Review Information → Notes"))
    out.append("Одно поле на платформу, на английском. Sign-in required — выключено (входа нет).\n")
    for platform, label, _ in PLATFORMS:
        out.append(heading(label, "-"))
        out.append(field("Notes", read(COPY / f"{platform}/review_notes.txt"), 4000))

    OUT.mkdir(parents=True)
    (OUT / "APP-STORE-TEXTS.txt").write_text("\n".join(out), encoding="utf-8")
    for platform, label, _ in PLATFORMS:
        for code, _, _ in LANGS:
            target = OUT / "screenshots" / label / code
            target.mkdir(parents=True)
            for source in sorted((SHOTS / platform / code / "screenshots").glob("*.png")):
                screen = source.stem.split(f"-{code}-", 1)[1]
                shutil.copy2(source, target / f"{SCREENS[screen]}.png")
    extra = OUT / "header-and-search-results"
    extra.mkdir()
    for name in ("kat-header-3840x1646.png", "kat-search-results-3840x2560.png"):
        shutil.copy2(COPY / "creative-assets" / name, extra / name)
    print(OUT)


if __name__ == "__main__":
    main()
