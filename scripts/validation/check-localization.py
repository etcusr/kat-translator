#!/usr/bin/env python3
"""Run from the project root. Check RU/EN/ES/TR coverage and interpolation safety."""
import importlib.util
import json
import re
import plistlib
import sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('literals', Path(__file__).with_name('swift-localization-literals.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
errors = []
count = 0
for path in [Path('assets/bundled/Localizable.xcstrings'), Path('apps/ios/Resources/InfoPlist.xcstrings')]:
    catalog = json.loads(path.read_text())
    assert catalog['sourceLanguage'] == 'ru'
    for key, entry in catalog['strings'].items():
        count += 1
        values = entry['localizations']
        if set(values) != {'ru', 'en', 'es', 'tr'}: errors.append(f'{key}: expected RU, EN, ES and TR')
        for language, value in values.items():
            units = [value['stringUnit']] if 'stringUnit' in value else [v['stringUnit'] for v in value['variations']['plural'].values()]
            for unit in units:
                if unit['state'] != 'translated' or not unit['value']: errors.append(f'{key}: empty {language}')
                if re.findall(r'%(?:@|lld)', key) != re.findall(r'%(?:@|lld)', unit['value']): errors.append(f'{key}: format arguments differ in {language}')
                if language in {'en', 'es', 'tr'} and re.search('[А-Яа-яЁё]', unit['value']): errors.append(f'{key}: Russian in English value')
ui = json.loads(Path('assets/bundled/Localizable.xcstrings').read_text())['strings']
for folder in ['shared/apple', 'apps/ios', 'apps/macos', 'shared/packages/OfflineCore/Sources/OfflineCore']:
    for path in Path(folder).rglob('*.swift'):
        if 'tests' in path.parts: continue
        # Language names are data for bilingual search. L10n owns plural lookup.
        if path.name in {'LanguageSelection.swift', 'L10n.swift', 'ASRComparisonProbe.swift'}: continue # Fixed developer audio/text fixtures are not UI copy.
        source = path.read_text()
        for start, end, key, raw, args in module.literals(source):
            if not source[:start].endswith('L10n.text('): errors.append(f'{path}: unlocalized {raw}')
            if key not in ui: errors.append(f'{path}: missing key {key}')
if len(sys.argv) > 1:
    bundle = Path(sys.argv[1])
    for catalog_path in [Path('assets/bundled/Localizable.xcstrings'), Path('apps/ios/Resources/InfoPlist.xcstrings')]:
        catalog = json.loads(catalog_path.read_text())
        for language in ['ru', 'en', 'es', 'tr']:
            compiled = plistlib.loads((bundle / (language + '.lproj') / (catalog_path.stem + '.strings')).read_bytes())
            for key, entry in catalog['strings'].items():
                unit = entry['localizations'][language].get('stringUnit')
                if unit and compiled.get(key) != unit['value']:
                    errors.append(f'{language}: compiled catalog mismatch: {key}')
assert not errors, '\n'.join(errors)
print(f'PASS: {count} catalog entries; RU/EN/ES/TR coverage, placeholders, UI literal coverage')
