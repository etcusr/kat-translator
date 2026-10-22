#!/usr/bin/env python3
"""Validate the prepared iOS/macOS App Store copy for every interface language."""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
COPY = ROOT / 'docs/publication/2026-10-14'
LOCALES = {'ru': 'ru', 'en': 'en-US', 'es': 'es-ES', 'tr': 'tr'}
LIMITS = {
    'name.txt': 30,
    'subtitle.txt': 30,
    'promotional_text.txt': 170,
    'description.txt': 4000,
    'keywords.txt': 100,
    'support_url.txt': 255,
    'marketing_url.txt': 255,
    'privacy_policy_url.txt': 255,
    'whats-new.txt': 4000,
}


def validate():
    rows, errors = [], []
    catalog = json.loads((ROOT / 'assets/bundled/Localizable.xcstrings').read_text())
    ui_languages = set().union(*(set(v.get('localizations', {})) for v in catalog['strings'].values()))
    if ui_languages != set(LOCALES):
        errors.append(f'UI languages changed: {sorted(ui_languages)}; update store copy and locale mapping')
    for language in LOCALES:
        for shared_field in ('name.txt', 'subtitle.txt', 'privacy_policy_url.txt'):
            ios = COPY / 'ios' / language / shared_field
            macos = COPY / 'macos' / language / shared_field
            if ios.exists() and macos.exists() and ios.read_bytes() != macos.read_bytes():
                errors.append(f'Shared App Information differs: {language}/{shared_field}')
    for platform in ('ios', 'macos'):
        for language, asc_locale in LOCALES.items():
            for filename, limit in LIMITS.items():
                path = COPY / platform / language / filename
                if not path.is_file():
                    errors.append(f'Missing: {path.relative_to(ROOT)}')
                    continue
                data = path.read_bytes()
                text = data.decode('utf-8').removesuffix('\n')
                units = len(text.encode('utf-16-le')) // 2
                byte_length = len(text.encode('utf-8'))
                # Match the saved ASC field counter and Apple's product-page guidance.
                # Keep UTF-8 byte length as evidence, not the UI character limit.
                count = max(len(text), units)
                if not text or text != text.strip():
                    errors.append(f'Empty value or extra surrounding whitespace: {path.relative_to(ROOT)}')
                if count > limit:
                    errors.append(f'{path.relative_to(ROOT)}: {count} exceeds {limit}')
                if filename == 'keywords.txt':
                    terms = text.split(',')
                    if any(not t or t != t.strip() for t in terms) or len(set(t.casefold() for t in terms)) != len(terms):
                        errors.append(f'Empty, duplicate or padded keyword: {path.relative_to(ROOT)}')
                if filename.endswith('_url.txt'):
                    parsed = urlparse(text)
                    if parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.password:
                        errors.append(f'Invalid HTTPS URL: {path.relative_to(ROOT)}')
                rows.append({'path': str(path.relative_to(ROOT)), 'app_store_locale': asc_locale,
                             'characters': len(text), 'utf16_units': units, 'utf8_bytes': byte_length,
                             'limit': limit, 'limit_unit': 'characters',
                             'sha256': hashlib.sha256(data).hexdigest()})
        notes = COPY / platform / 'review_notes.txt'
        text = notes.read_text().strip() if notes.exists() else ''
        if not text or len(text.encode('utf-16-le')) // 2 > 4000:
            errors.append(f'Missing/oversized reviewer notes: {notes.relative_to(ROOT)}')
        legacy = COPY / platform / ('en' if platform == 'ios' else 'ru') / 'review_notes.txt'
        if not legacy.exists() or legacy.read_text().strip() != text:
            errors.append(f'Legacy reviewer-notes link differs: {legacy.relative_to(ROOT)}')
    return {'localizations': 8, 'fields': rows, 'review_notes_checked': 2,
            'checks': 'Required fields, interface-language parity, character limits with UTF-8 byte counts, HTTPS URL syntax and reviewer-note copies',
            'limitations': 'No App Store upload, URL availability test or native-speaker review is implied.',
            'errors': errors}


def main():
    global COPY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, help='Write validation counts and source hashes as JSON')
    parser.add_argument('--copy-root', type=Path, default=COPY, help='Prepared metadata directory')
    args = parser.parse_args()
    COPY = args.copy_root.resolve()
    result = validate()
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    if result['errors']:
        raise SystemExit('\n'.join(result['errors']))
    print(f"PASS: 8 localizations, {len(result['fields'])} fields, 2 platform reviewer notes; RU/EN/ES/TR match the interface")


if __name__ == '__main__':
    main()
