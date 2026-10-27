#!/usr/bin/env python3
"""Offline checks for localization, release configuration and source hygiene."""
import base64
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'Config/Release.json').read_text())
assert re.fullmatch(r'\d+\.\d+\.\d+', config['version'])
assert config['build'].isdigit()
assert re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', config['repository'])
assert len(base64.b64decode((root / 'Config/UpdatePublicKey.txt').read_text().strip(), validate=True)) == 32
catalog = json.loads((root / 'Config/English.json').read_text())
for key, value in catalog.items():
    assert sorted(re.findall(r'%(?:ld|@)', key)) == sorted(re.findall(r'%(?:ld|@)', value)), key
for language in ['it', 'en']:
    expected = '\n'.join(f'{json.dumps(key, ensure_ascii=False)} = {json.dumps(value if language == "en" else key, ensure_ascii=False)};' for key, value in sorted(catalog.items())) + '\n'
    actual = (root / f'Sources/Resonance/Resources/{language}.lproj/Localizable.strings').read_text()
    assert actual == expected, 'Regenerate localization tables'
view = (root / 'Sources/Resonance/ContentView.swift').read_text()
assert 'File scaricati' not in view
assert 'Picker("Lingua"' in view
manifest = json.loads((root / 'vendor/manifest.json').read_text())
for asset in manifest['assets']:
    assert asset['url'].startswith('https://')
    assert re.fullmatch(r'[a-f0-9]{64}', asset['sha256'])
tracked = subprocess.run(['git', 'ls-files'], cwd=root, capture_output=True, text=True, check=True).stdout.splitlines()
for path in tracked:
    assert not path.startswith(('.private/', 'research/', 'vendor/bin/', 'vendor/cache/', 'dist/')), path
    assert not path.endswith(('.p12', '.p8', '.key')), path
print(f'PASS: {len(catalog)} bilingual strings, release configuration, pinned dependencies, source hygiene.')
