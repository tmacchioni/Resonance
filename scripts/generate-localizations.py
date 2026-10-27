#!/usr/bin/env python3
"""Keep native localization tables aligned; Config/English.json is the editable catalog."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / 'Config/English.json').read_text())
for language in ['it', 'en']:
    folder = root / 'Sources/Resonance/Resources' / f'{language}.lproj'
    folder.mkdir(parents=True, exist_ok=True)
    entries = [f'{json.dumps(key, ensure_ascii=False)} = {json.dumps(value if language == "en" else key, ensure_ascii=False)};' for key, value in sorted(catalog.items())]
    (folder / 'Localizable.strings').write_text('\n'.join(entries) + '\n')
