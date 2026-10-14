#!/usr/bin/env python3
"""Generate Android metadata from shared Swift catalogs; never copy model weights."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
core = ROOT / 'shared/packages/OfflineCore/Sources/OfflineCore'
languages = (core / 'LanguageSelection.swift').read_text()
recognition = (core / 'RecognitionCatalog.swift').read_text()
coordinator = (ROOT / 'shared/apple/Models/PackageDownloadCoordinator.swift').read_text()
wayu = (ROOT / 'shared/apple/Models/WayuCatalog.swift').read_text()
whisper = dict(re.findall(r'\.init\(id: "([^"]+)"[^\n]+whisperCode: "([^"]+)"', languages))
index = re.findall(r'\.init\(id: "([^"]+)"[^\n]+indexName: "[^"]+"', languages)
ultra = re.findall(r'"([^"]+)"', recognition.split('ultraLanguages: Set<String> = [')[1].split(']')[0])
omni_section = recognition.split('omnilingualCodes: [String: String] = [')[1].split(']')[0]
omni = dict(re.findall(r'"([^"]+)": "([^"]+)"', omni_section))
supertonic = ['ru', 'en'] + re.findall(r'"([^"]+)"', coordinator.split('let supertonicLanguages: Set<String> = [')[1].split(']')[0])
parts = []
for ident, title, url, size, sha in re.findall(r'ModelDescriptor\(id: "([^"]+)", title: L10n.text\("([^"]+)"\),\s*remoteURL: URL\(string: "([^"]+)"\)!,\s*byteCount: (\d+), sha256: "([^"]+)"', wayu):
    parts.append(dict(id=ident, title=title, path=ident+'.bin', remoteURL=url, byteCount=int(size), sha256=sha))
assert len(whisper) > 80 and len(omni) > 30 and len(supertonic) == 31 and len(parts) == 4
data = dict(schemaVersion=1, generatedBy='scripts/android/generate-package-capabilities.py', index=index, ultra=ultra, whisper=whisper, omnilingual=omni, supertonic=supertonic, wayu=parts)
output = ROOT / 'assets/catalogs/android-capabilities.json'
body = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
if parser.parse_args().check:
    assert output.read_text() == body, 'Run scripts/android/generate-package-capabilities.py'
else:
    output.write_text(body)
print('Android package capabilities match shared catalogs')
